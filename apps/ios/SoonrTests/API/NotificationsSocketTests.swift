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
            await connector.urls.first?.absoluteString
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
            await connector.urls.first?.absoluteString
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

        let sent = try #require(await connector.sent.first)
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
        #expect(await connector.urls.count == 1)
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
        #expect(await connector.urls.count == 2)
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
        #expect(await connector.urls.count == 1)
    }

    @Test
    func backoffGrowsAndThenHoldsAtThirtySeconds() {
        #expect(NotificationsSocket.exponentialBackoff(failures: 1) == .seconds(1))
        #expect(NotificationsSocket.exponentialBackoff(failures: 2) == .seconds(2))
        #expect(NotificationsSocket.exponentialBackoff(failures: 4) == .seconds(8))
        #expect(NotificationsSocket.exponentialBackoff(failures: 9) == .seconds(30))
    }

    @Test
    func endingTheIterationClosesTheConnection() async throws {
        let connector = StubConnector(script: [[.text(ready), .text(recordsChanged), .hold]])
        let socket = makeSocket(connector: connector)

        for await _ in socket.notificationEvents() {
            break
        }

        try await waitUntil { await connector.cancellations >= 1 }
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

        try await waitUntil { await connector.urls.isEmpty == false }
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
private actor StubConnector: WebSocketConnecting {
    private(set) var urls: [URL] = []
    private(set) var sent: [String] = []
    private(set) var cancellations = 0

    private var script: [[StubFrame]]

    init(script: [[StubFrame]]) {
        self.script = script
    }

    nonisolated func connect(to url: URL) -> any WebSocketChannel {
        let frames = StubChannel(connector: self)
        Task { await register(url: url, channel: frames) }
        return frames
    }

    private func register(url: URL, channel: StubChannel) async {
        urls.append(url)
        let frames = script.isEmpty ? [.hold] : script.removeFirst()
        await channel.load(frames)
    }

    func record(sent text: String) {
        self.sent.append(text)
    }

    func recordCancellation() {
        cancellations += 1
    }
}

private actor StubChannel: WebSocketChannel {
    private let connector: StubConnector
    private var frames: [StubFrame] = []
    private var isLoaded = false

    init(connector: StubConnector) {
        self.connector = connector
    }

    func load(_ frames: [StubFrame]) {
        self.frames = frames
        isLoaded = true
    }

    nonisolated func send(_ text: String) async throws {
        await connector.record(sent: text)
    }

    nonisolated func receive() async throws -> String {
        try await next()
    }

    nonisolated func cancel() {
        Task { await connector.recordCancellation() }
    }

    private func next() async throws -> String {
        while isLoaded == false {
            try await Task.sleep(for: .milliseconds(1))
        }

        guard frames.isEmpty == false else {
            try await Task.sleep(for: .seconds(60))
            throw CancellationError()
        }

        switch frames.removeFirst() {
        case let .text(text):
            return text
        case .close:
            throw URLError(.networkConnectionLost)
        case .hold:
            try await Task.sleep(for: .seconds(60))
            throw CancellationError()
        }
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
