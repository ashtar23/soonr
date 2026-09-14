import Foundation
import Testing

@testable import Soonr

@MainActor
@Suite
struct NotificationsRealtimeTests {
    @Test
    func aRecordsEventReloadsTheList() async throws {
        let world = World()
        await world.records.load()
        world.realtime.start()

        await world.send(.recordsChanged)

        try await world.waitUntil { await world.notifications.loads == 2 }
        #expect(world.records.state.records?.map(\.id) == ["notification-1"])
    }

    @Test
    func aPreferencesEventAdoptsWhatTheServerSent() async throws {
        let world = World()
        await world.preferences.load()
        world.realtime.start()

        await world.send(.preferencesChanged(.pushOnly))

        try await world.waitUntil { world.preferences.preferences == .pushOnly }
        // Adopting what arrived means no request of our own.
        #expect(await world.notifications.preferenceLoads == 1)
    }

    /// The event says preferences moved but not to what, so the server is the
    /// only place the answer is.
    @Test
    func aPreferencesEventWithoutACopyRefetches() async throws {
        let world = World()
        await world.preferences.load()
        world.realtime.start()

        await world.send(.preferencesChanged(nil))

        try await world.waitUntil { await world.notifications.preferenceLoads == 2 }
    }

    /// The scene becoming active is one of the callers, and that happens more
    /// than once per launch.
    @Test
    func startingTwiceKeepsOneConnection() async throws {
        let world = World()

        world.realtime.start()
        world.realtime.start()

        try await world.waitUntil { await world.stream.subscriptions == 1 }
        #expect(await world.stream.subscriptions == 1)
    }

    @Test
    func stoppingEndsTheSubscription() async throws {
        let world = World()
        world.realtime.start()
        try await world.waitUntil { await world.stream.subscriptions == 1 }

        world.realtime.stop()

        #expect(world.realtime.isRunning == false)
        try await world.waitUntil { await world.stream.isFinished }
    }

    @Test
    func stoppingAndStartingAgainReconnects() async throws {
        let world = World()
        world.realtime.start()
        try await world.waitUntil { await world.stream.subscriptions == 1 }
        world.realtime.stop()

        world.realtime.start()

        try await world.waitUntil { await world.stream.subscriptions == 2 }
    }
}

@MainActor
private struct World {
    let notifications = StubNotificationsService()
    let stream = StubStream()
    let records: NotificationsStore
    let preferences: NotificationPreferencesStore
    let realtime: NotificationsRealtime

    init() {
        records = NotificationsStore(notifications: notifications)
        preferences = NotificationPreferencesStore(
            notifications: notifications,
            saveDelay: .seconds(60)
        )
        realtime = NotificationsRealtime(
            stream: stream,
            records: records,
            preferences: preferences
        )
    }

    func send(_ event: NotificationStreamEvent) async {
        try? await waitUntil { await stream.subscriptions >= 1 }
        await stream.send(event)
    }

    func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<400 where await condition() == false {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(await condition())
    }
}

private actor StubStream: NotificationStreaming {
    private(set) var subscriptions = 0
    private(set) var isFinished = false
    private var continuation: AsyncStream<NotificationStreamEvent>.Continuation?

    nonisolated func notificationEvents() -> AsyncStream<NotificationStreamEvent> {
        let (stream, continuation) = AsyncStream<NotificationStreamEvent>.makeStream()
        Task { await register(continuation) }
        return stream
    }

    private func register(_ continuation: AsyncStream<NotificationStreamEvent>.Continuation) {
        subscriptions += 1
        isFinished = false
        self.continuation = continuation
        continuation.onTermination = { _ in
            Task { await self.markFinished() }
        }
    }

    private func markFinished() {
        isFinished = true
    }

    func send(_ event: NotificationStreamEvent) {
        continuation?.yield(event)
    }
}

private actor StubNotificationsService: NotificationsReading, NotificationPreferencesProviding {
    private(set) var loads = 0
    private(set) var preferenceLoads = 0

    func notifications(
        after _: String?,
        unreadOnly _: Bool
    ) async throws -> Page<NotificationRecord> {
        loads += 1
        return Page(items: [.realtimeSample])
    }

    func notifications(about _: String) async throws -> [NotificationRecord] {
        [.realtimeSample]
    }

    func unreadNotificationCount() async throws -> Int { 1 }

    func markNotificationRead(id _: String) async throws -> NotificationRecord {
        .realtimeSample
    }

    func markAllNotificationsRead() async throws -> Int { 0 }

    func notificationPreferences() async throws -> NotificationPreferences {
        preferenceLoads += 1
        return .everything
    }

    func updateNotificationPreferences(
        _ preferences: NotificationPreferences
    ) async throws -> NotificationPreferences {
        preferences
    }
}

extension NotificationPreferences {
    fileprivate static let everything = NotificationPreferences(
        channels: .init(inApp: true, push: true),
        events: .init(releaseDateChanged: true, releaseApproaching: true),
        timingPresets: [.onDay]
    )

    fileprivate static let pushOnly = NotificationPreferences(
        channels: .init(inApp: false, push: true),
        events: .init(releaseDateChanged: false, releaseApproaching: true),
        timingPresets: [.days7Before]
    )
}

extension NotificationRecord {
    fileprivate static let realtimeSample = NotificationRecord(
        id: "notification-1",
        eventType: .releaseApproaching,
        destinationTitleID: "rawg:1",
        titleName: "Hades II",
        titleArtworkURL: nil,
        message: "Release approaching",
        subtitle: nil,
        payload: .releaseApproaching(targetReleaseDate: "2026-01-05"),
        createdAt: "2026-01-03T12:00:00.000Z",
        readAt: nil
    )
}
