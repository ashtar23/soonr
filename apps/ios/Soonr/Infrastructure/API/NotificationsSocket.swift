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

    init(
        configuration: AppConfiguration,
        accessToken: @escaping AccessTokenProvider,
        connector: any WebSocketConnecting = URLSessionWebSocketConnector(),
        backoff: @escaping Backoff = NotificationsSocket.exponentialBackoff
    ) {
        self.configuration = configuration
        self.accessToken = accessToken
        self.connector = connector
        self.backoff = backoff
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
            do {
                try await readUntilClosed(yielding: continuation) {
                    // Reached only once the server accepts the token, so a
                    // connection that fails the handshake every time keeps
                    // backing off instead of retrying in a tight loop.
                    failures = 0
                }
            } catch is CancellationError {
                return
            } catch {
                AppLog.notifications.error("Notifications stream dropped: \(error)")
            }

            failures += 1

            do {
                try await Task.sleep(for: backoff(failures))
            } catch {
                return
            }
        }
    }

    /// One connection: authenticate, then yield events until it ends.
    private func readUntilClosed(
        yielding continuation: AsyncStream<NotificationStreamEvent>.Continuation,
        onReady: () -> Void
    ) async throws {
        guard let token = await accessToken() else {
            throw APIError.unauthorized
        }

        let channel = connector.connect(to: try streamURL())
        defer { channel.cancel() }

        try await channel.send(
            String(decoding: JSONEncoder().encode(AuthMessage(accessToken: token)), as: UTF8.self))

        while true {
            try Task.checkCancellation()

            switch try decode(try await channel.receive()) {
            case .ready:
                onReady()
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
    static func exponentialBackoff(failures: Int) -> Duration {
        .seconds(min(30, 1 << min(failures - 1, 5)))
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
