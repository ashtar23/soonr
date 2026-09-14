import Foundation
import Testing

@testable import Soonr

@Suite(.tags(.networking))
struct NotificationsSocketTests {
    @Test
    func theSocketOpensAgainstTheAPIHostOverTLS() async throws {
        let connector = StubConnector(script: [[.hold]])
        let socket = makeSocket(connector: connector)

        try await openOneConnection(to: socket, connector: connector)

        #expect(
            connector.urls.first?.absoluteString
                == "wss://api.example.com/notifications/stream"
        )
    }

    @Test
    func aPlainHTTPBaseURLOpensAnUnencryptedSocket() async throws {
        let connector = StubConnector(script: [[.hold]])
        let socket = makeSocket(
            baseURL: URL(string: "http://localhost:3000")!,
            connector: connector
        )

        try await openOneConnection(to: socket, connector: connector)

        #expect(
            connector.urls.first?.absoluteString
                == "ws://localhost:3000/notifications/stream"
        )
    }

    /// The server closes a connection that has not authenticated within five
    /// seconds, so the token goes first, before anything is read.
    @Test
    func theTokenIsSentAsTheFirstMessage() async throws {
        let connector = StubConnector(script: [[.text(ready), .text(recordsChanged), .close]])
        let socket = makeSocket(connector: connector)

        _ = await firstEvents(1, from: socket, connector: connector)

        let sent = try #require(connector.sent.first)
        let payload = try JSONDecoder().decode(
            AuthPayload.self,
            from: Data(sent.utf8)
        )
        #expect(payload.type == "auth")
        #expect(payload.accessToken == "token-1")
    }

    @Test
    func aRecordsChangeIsReported() async throws {
        let connector = StubConnector(script: [[.text(ready), .text(recordsChanged), .close]])
        let socket = makeSocket(connector: connector)

        let events = await firstEvents(1, from: socket, connector: connector)

        #expect(events == [.recordsChanged])
    }

    @Test
    func aPreferencesChangeCarriesTheNewPreferences() async throws {
        let connector = StubConnector(script: [[.text(ready), .text(preferencesChanged), .close]])
        let socket = makeSocket(connector: connector)

        let events = await firstEvents(1, from: socket, connector: connector)

        #expect(
            events == [
                .preferencesChanged(
                    NotificationPreferences(
                        channels: .init(inApp: true, push: false),
                        events: .init(releaseDateChanged: true, releaseApproaching: true),
                        timingPresets: [.onDay, .days7Before]
                    )
                )
            ]
        )
    }

    /// Losing the preferences must not also lose the news that they changed.
    @Test
    func unreadablePreferencesStillReportTheChange() async throws {
        let message = #"{"type":"notifications.changed","scope":"preferences","preferences":7}"#
        let connector = StubConnector(script: [[.text(ready), .text(message), .close]])
        let socket = makeSocket(connector: connector)

        let events = await firstEvents(1, from: socket, connector: connector)

        #expect(events == [.preferencesChanged(nil)])
    }

    @Test
    func aPongDoesNotSurfaceAsAnEvent() async throws {
        let connector = StubConnector(
            script: [[.text(ready), .text(#"{"type":"pong"}"#), .text(recordsChanged), .close]]
        )
        let socket = makeSocket(connector: connector)

        let events = await firstEvents(1, from: socket, connector: connector)

        #expect(events == [.recordsChanged])
    }

    /// A newer server sending something this build has no meaning for must not
    /// take the connection down with it.
    @Test
    func anUnrecognizedMessageIsIgnoredRatherThanFatal() async throws {
        let connector = StubConnector(
            script: [
                [
                    .text(ready), .text(#"{"type":"notifications.archived"}"#),
                    .text(recordsChanged), .close,
                ]
            ]
        )
        let socket = makeSocket(connector: connector)

        let events = await firstEvents(1, from: socket, connector: connector)

        #expect(events == [.recordsChanged])
        #expect(connector.urls.count == 1)
    }

    @Test
    func aDroppedConnectionIsReopenedAndKeepsDelivering() async throws {
        let connector = StubConnector(
            script: [
                [.text(ready), .close],
                [.text(ready), .text(recordsChanged), .close],
            ]
        )
        let socket = makeSocket(connector: connector)

        let events = await firstEvents(1, from: socket, connector: connector)

        #expect(events == [.recordsChanged])
        #expect(connector.urls.count == 2)
    }

    /// A token that has gone away is a reason to wait, not to spin.
    @Test
    func noSessionMeansNoConnectionIsOpened() async throws {
        let connector = StubConnector(script: [[.text(ready), .text(recordsChanged), .close]])
        let tokens = TokenSequence(["nil", "token-1"])
        let socket = NotificationsSocket(
            configuration: configuration(),
            accessToken: { await tokens.next() },
            connector: connector,
            backoff: { _ in .zero }
        )

        let events = await firstEvents(1, from: socket, connector: connector)

        #expect(events == [.recordsChanged])
        // The first attempt never reached the connector.
        #expect(connector.urls.count == 1)
    }

    /// A socket idling behind NAT is dropped without either end being told, so
    /// something has to write to find out.
    @Test
    func aQuietConnectionIsPinged() async throws {
        let connector = StubConnector(script: [[.text(ready), .hold]])
        let socket = NotificationsSocket(
            configuration: configuration(),
            accessToken: { "token-1" },
            connector: connector,
            backoff: { _ in .zero },
            pingInterval: .milliseconds(5)
        )

        let reader = Task {
            for await _ in socket.notificationEvents() {}
        }
        defer { reader.cancel() }

        try await waitUntil { connector.sent.contains(#"{"type":"ping"}"#) }
    }

    @Test
    func backoffGrowsAndThenHoldsAtThirtySeconds() {
        #expect(NotificationsSocket.delay(failures: 1, spread: 1) == .seconds(1))
        #expect(NotificationsSocket.delay(failures: 2, spread: 1) == .seconds(2))
        #expect(NotificationsSocket.delay(failures: 4, spread: 1) == .seconds(8))
        #expect(NotificationsSocket.delay(failures: 9, spread: 1) == .seconds(30))
    }

    /// Every client connected to a server when it restarted starts counting
    /// from the same moment, so without a spread they all come back together.
    @Test
    func backoffIsSpreadSoClientsDoNotReturnInStep() {
        let delays = (0..<40).map { _ in
            NotificationsSocket.exponentialBackoff(failures: 4)
        }

        #expect(Set(delays).count > 1)
        #expect(delays.allSatisfy { $0 >= .seconds(6.4) && $0 <= .seconds(9.6) })
    }

    @Test
    func thespreadScalesTheDelayRatherThanReplacingIt() {
        #expect(NotificationsSocket.delay(failures: 3, spread: 0.8) == .seconds(3.2))
        #expect(NotificationsSocket.delay(failures: 3, spread: 1.2) == .seconds(4.8))
    }

    /// A half-open socket takes writes and answers nothing, so a ping that
    /// succeeds proves less than it looks like it does.
    @Test
    func asocketThatStopsAnsweringIsDropped() async throws {
        let connector = StubConnector(script: [[.text(ready), .hold], [.text(ready), .hold]])
        let socket = NotificationsSocket(
            configuration: configuration(),
            accessToken: { "token-1" },
            connector: connector,
            backoff: { _ in .zero },
            pingInterval: .milliseconds(5),
            pongTimeout: .milliseconds(20)
        )

        let reader = Task {
            for await _ in socket.notificationEvents() {}
        }
        defer { reader.cancel() }

        // Silence past the deadline ends the connection, and the next one opens.
        try await waitUntil { connector.urls.count >= 2 }
    }

    /// A token the server keeps refusing keeps being refused, and retrying
    /// every thirty seconds for as long as the app is open helps nobody.
    @Test
    func itgivesUpAfterEnoughRefusals() async throws {
        let refusal = #"{"type":"error","message":"Authentication failed."}"#
        let connector = StubConnector(
            script: Array(repeating: [.text(refusal)], count: 20)
        )
        let socket = NotificationsSocket(
            configuration: configuration(),
            accessToken: { "token-1" },
            connector: connector,
            backoff: { _ in .zero },
            attemptLimit: 4
        )

        // The stream ends by itself rather than the reader stopping it.
        for await _ in socket.notificationEvents() {}

        #expect(connector.urls.count == 4)
    }

    @Test
    func endingTheIterationClosesTheConnection() async throws {
        let connector = StubConnector(script: [[.text(ready), .text(recordsChanged), .hold]])
        let socket = makeSocket(connector: connector)

        for await _ in socket.notificationEvents() {
            break
        }

        try await waitUntil { connector.cancellations >= 1 }
    }

    // MARK: - Helpers

    private let ready = #"{"type":"ready"}"#
    private let recordsChanged = #"{"type":"notifications.changed","scope":"records"}"#
    private let preferencesChanged = """
        {"type":"notifications.changed","scope":"preferences","preferences":\
        {"channels":{"inApp":true,"push":false},\
        "events":{"releaseDateChanged":true,"releaseApproaching":true},\
        "timingPresets":["on_day","days_7_before"],"updatedAt":"2026-01-03T12:00:00.000Z"}}
        """

    private func configuration(
        baseURL: URL = URL(string: "https://api.example.com")!
    ) -> AppConfiguration {
        AppConfiguration(apiBaseURL: baseURL, supabase: nil)
    }

    private func makeSocket(
        baseURL: URL = URL(string: "https://api.example.com")!,
        connector: StubConnector
    ) -> NotificationsSocket {
        NotificationsSocket(
            configuration: configuration(baseURL: baseURL),
            accessToken: { "token-1" },
            connector: connector,
            backoff: { _ in .zero }
        )
    }

    private func firstEvents(
        _ count: Int,
        from socket: NotificationsSocket,
        connector _: StubConnector
    ) async -> [NotificationStreamEvent] {
        var events: [NotificationStreamEvent] = []

        for await event in socket.notificationEvents() {
            events.append(event)
            if events.count == count {
                break
            }
        }

        return events
    }

    /// Starts the stream only long enough for one connection to be opened,
    /// for the tests that care about the connection rather than its messages.
    private func openOneConnection(
        to socket: NotificationsSocket,
        connector: StubConnector
    ) async throws {
        let reader = Task {
            for await _ in socket.notificationEvents() {}
        }
        defer { reader.cancel() }

        try await waitUntil { connector.urls.isEmpty == false }
    }

    private func waitUntil(
        _ condition: @Sendable () async -> Bool
    ) async throws {
        for _ in 0..<200 where await condition() == false {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(await condition())
    }
}

private struct AuthPayload: Decodable {
    let type: String
    let accessToken: String
}

private enum StubFrame: Sendable {
    case text(String)
    /// The connection ends, which is what a reconnect is made of.
    case close
    /// Stays open with nothing more to say.
    case hold
}

/// Hands out one scripted connection per `connect`, so a test can say what the
/// second attempt sees as well as the first.
///
/// Locked rather than an actor so that `connect` can take its script in the
/// same step it is called: handing the channel back before it knows its frames
/// would put a race in the scaffolding rather than in the code under test.
private final class StubConnector: WebSocketConnecting, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [[StubFrame]]
    private var openedURLs: [URL] = []
    private var sentText: [String] = []
    private var cancelCount = 0

    init(script: [[StubFrame]]) {
        self.script = script
    }

    var urls: [URL] { lock.withLock { openedURLs } }
    var sent: [String] { lock.withLock { sentText } }
    var cancellations: Int { lock.withLock { cancelCount } }

    func connect(to url: URL) -> any WebSocketChannel {
        let frames: [StubFrame] = lock.withLock {
            openedURLs.append(url)
            return script.isEmpty ? [.hold] : script.removeFirst()
        }

        return StubChannel(connector: self, frames: frames)
    }

    func record(sent text: String) {
        lock.withLock { sentText.append(text) }
    }

    func recordCancellation() {
        lock.withLock { cancelCount += 1 }
    }
}

private final class StubChannel: WebSocketChannel, @unchecked Sendable {
    private let connector: StubConnector
    private let lock = NSLock()
    private var frames: [StubFrame]

    init(connector: StubConnector, frames: [StubFrame]) {
        self.connector = connector
        self.frames = frames
    }

    func send(_ text: String) async throws {
        connector.record(sent: text)
    }

    func receive() async throws -> String {
        let next: StubFrame? = lock.withLock {
            frames.isEmpty ? nil : frames.removeFirst()
        }

        switch next {
        case let .text(text):
            return text
        case .close:
            throw URLError(.networkConnectionLost)
        case .hold, .none:
            // Open with nothing to say, until the reader is cancelled.
            try await Task.sleep(for: .seconds(60))
            throw CancellationError()
        }
    }

    func cancel() {
        connector.recordCancellation()
    }
}

private actor TokenSequence {
    private var values: [String]

    init(_ values: [String]) {
        self.values = values
    }

    func next() -> String? {
        guard values.isEmpty == false else {
            return nil
        }

        let value = values.removeFirst()
        return value == "nil" ? nil : value
    }
}
