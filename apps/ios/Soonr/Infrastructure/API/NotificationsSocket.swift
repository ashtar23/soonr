import Foundation

/// The client half of `GET /notifications/stream`.
///
/// The socket is authenticated by a message rather than a header: the server
/// gives a new connection five seconds to send one and closes it otherwise, so
/// the token is fetched per attempt and a reconnect after a long sleep carries
/// a fresh one.
struct NotificationsSocket: NotificationStreaming, Sendable {
    typealias AccessTokenProvider = @Sendable () async -> String?
    /// How long to wait before a retry, given how many have already failed.
    /// Injected so tests do not spend the wait.
    typealias Backoff = @Sendable (Int) -> Duration

    private let configuration: AppConfiguration
    private let connector: any WebSocketConnecting
    private let accessToken: AccessTokenProvider
    private let backoff: Backoff
    private let pingInterval: Duration
    private let pongTimeout: Duration
    private let attemptLimit: Int

    init(
        configuration: AppConfiguration,
        accessToken: @escaping AccessTokenProvider,
        connector: any WebSocketConnecting = URLSessionWebSocketConnector(),
        backoff: @escaping Backoff = NotificationsSocket.exponentialBackoff,
        pingInterval: Duration = .seconds(30),
        pongTimeout: Duration = .seconds(10),
        attemptLimit: Int = 10
    ) {
        self.configuration = configuration
        self.accessToken = accessToken
        self.connector = connector
        self.backoff = backoff
        self.pingInterval = pingInterval
        self.pongTimeout = pongTimeout
        self.attemptLimit = attemptLimit
    }

    func notificationEvents() -> AsyncStream<NotificationStreamEvent> {
        AsyncStream { continuation in
            let task = Task {
                await connectRepeatedly(yielding: continuation)
                continuation.finish()
            }

            // Ending the iteration is the only stop signal the consumer has.
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Runs until cancelled. A connection ending is ordinary — a phone changing
    /// network does it — so it is answered by reconnecting rather than by
    /// giving up and leaving the screen silently stale.
    private func connectRepeatedly(
        yielding continuation: AsyncStream<NotificationStreamEvent>.Continuation
    ) async {
        var failures = 0

        while Task.isCancelled == false {
            let readiness = Readiness()

            do {
                try await readUntilClosed(yielding: continuation, readiness: readiness)
            } catch is CancellationError {
                return
            } catch {
                AppLog.notifications.error("Notifications stream dropped: \(error)")
            }

            // Only a connection the server accepted earns a fresh start, so one
            // failing the handshake every time keeps backing off rather than
            // retrying in a tight loop.
            if await readiness.isReady {
                failures = 0
            }

            failures += 1

            // A token the server keeps refusing will keep being refused. Giving
            // up ends the stream rather than retrying every thirty seconds for
            // as long as the app is open; the app opens it again when the scene
            // next becomes active, which is when something may have changed.
            guard failures < attemptLimit else {
                AppLog.notifications.error(
                    "Notifications stream gave up after \(failures) attempts"
                )
                return
            }

            do {
                try await Task.sleep(for: backoff(failures))
            } catch {
                return
            }
        }
    }

    /// One connection: authenticate, then yield events until it ends, with a
    /// heartbeat running alongside the reader.
    private func readUntilClosed(
        yielding continuation: AsyncStream<NotificationStreamEvent>.Continuation,
        readiness: Readiness
    ) async throws {
        guard let token = await accessToken() else {
            throw APIError.unauthorized
        }

        let channel = connector.connect(to: try streamURL())
        defer { channel.cancel() }

        let auth = try JSONEncoder().encode(AuthMessage(accessToken: token))
        try await channel.send(String(decoding: auth, as: UTF8.self))

        let liveness = Liveness()

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await keepAlive(on: channel, liveness: liveness)
            }

            group.addTask {
                try await read(
                    from: channel,
                    yielding: continuation,
                    readiness: readiness,
                    liveness: liveness
                )
            }

            defer { group.cancelAll() }
            // Either one finishing ends this connection: the reader only stops
            // when the socket does, and the heartbeat only when a send fails.
            try await group.next()
        }
    }

    private func read(
        from channel: any WebSocketChannel,
        yielding continuation: AsyncStream<NotificationStreamEvent>.Continuation,
        readiness: Readiness,
        liveness: Liveness
    ) async throws {
        while true {
            try Task.checkCancellation()

            let message = try await channel.receive()
            // Anything at all proves the connection is carrying; a pong is only
            // the cheapest thing the server can send to prove it.
            await liveness.heard()

            switch try decode(message) {
            case .ready:
                await readiness.markReady()
            case .pong:
                continue
            case let .changed(event):
                continuation.yield(event)
            case let .failed(message):
                throw APIError.requestFailed(statusCode: 0, message: message)
            case .unrecognized:
                // A message this build has no meaning for is not a reason to
                // drop a working connection.
                continue
            }
        }
    }

    /// A socket idling behind NAT is dropped without either end being told, and
    /// the app would only find out at the next read — which, on a stream that
    /// is quiet by nature, could be hours. Writing on a timer surfaces a dead
    /// connection as a failed send.
    ///
    /// A send that succeeds is not proof of much, though: a half-open socket
    /// accepts writes and answers nothing. So the ping is a question, and
    /// silence after it is the answer that ends the connection.
    private func keepAlive(
        on channel: any WebSocketChannel,
        liveness: Liveness
    ) async throws {
        while true {
            try await Task.sleep(for: pingInterval)
            try await channel.send(#"{"type":"ping"}"#)

            try await Task.sleep(for: pongTimeout)

            if await liveness.silent(for: pongTimeout) {
                throw APIError.invalidResponse
            }
        }
    }

    private func streamURL() throws -> URL {
        var components = URLComponents(
            url: configuration.apiBaseURL.appending(path: "notifications/stream"),
            resolvingAgainstBaseURL: false
        )
        components?.scheme = configuration.apiBaseURL.scheme == "http" ? "ws" : "wss"

        guard let url = components?.url else {
            throw APIError.invalidRequest
        }

        return url
    }

    /// Doubling from one second, capped: a server that is down stays polled at
    /// a rate that does not matter, and one that blinked is back quickly.
    ///
    /// Spread, because every client that was connected to a server when it
    /// restarted starts counting from the same moment. Without it they all
    /// return together, at one second, then two, then four — the restarted
    /// server meeting the whole fleet at once, repeatedly.
    static func exponentialBackoff(failures: Int) -> Duration {
        delay(failures: failures, spread: .random(in: 0.8...1.2))
    }

    /// Separated from the spread so the curve can be checked without chance
    /// deciding what the answer is.
    static func delay(failures: Int, spread: Double) -> Duration {
        let seconds = Double(min(30, 1 << min(max(failures, 1) - 1, 5)))
        return .seconds(seconds * spread)
    }
}

/// When the connection last carried anything, which is the only evidence that
/// it still exists: a socket dropped behind NAT accepts writes and answers
/// nothing.
private actor Liveness {
    private var lastHeard = ContinuousClock.now

    func heard() {
        lastHeard = .now
    }

    func silent(for duration: Duration) -> Bool {
        ContinuousClock.now - lastHeard > duration
    }
}

/// Whether the server accepted this connection, which decides if the next
/// failure starts the backoff over.
private actor Readiness {
    private(set) var isReady = false

    func markReady() {
        isReady = true
    }
}

private struct AuthMessage: Encodable {
    let type = "auth"
    let accessToken: String
}

private enum ServerMessage {
    case ready
    case pong
    case changed(NotificationStreamEvent)
    case failed(String)
    case unrecognized
}

private struct ServerMessagePayload: Decodable {
    let type: String
    let scope: String?
    let message: String?
    let preferences: NotificationPreferences?

    private enum CodingKeys: String, CodingKey {
        case type
        case scope
        case message
        case preferences
    }

    /// Preferences this build cannot read leave the event standing without
    /// them, which the reader answers by refetching. Failing the whole message
    /// would instead drop the news that anything changed at all.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        scope = try? container.decodeIfPresent(String.self, forKey: .scope)
        message = try? container.decodeIfPresent(String.self, forKey: .message)
        preferences = try? container.decodeIfPresent(
            NotificationPreferences.self,
            forKey: .preferences
        )
    }
}

private func decode(_ text: String) throws -> ServerMessage {
    guard let payload = try? JSONDecoder().decode(ServerMessagePayload.self, from: Data(text.utf8))
    else {
        throw APIError.invalidPayload
    }

    switch payload.type {
    case "ready":
        return .ready
    case "pong":
        return .pong
    case "error":
        return .failed(payload.message ?? "The notifications stream was refused.")
    case "notifications.changed":
        switch payload.scope {
        case "records":
            return .changed(.recordsChanged)
        case "preferences":
            return .changed(.preferencesChanged(payload.preferences))
        default:
            return .unrecognized
        }
    default:
        return .unrecognized
    }
}
