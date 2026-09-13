import Foundation
import Testing

@testable import Soonr

@MainActor
@Suite(.tags(.networking))
struct NotificationsStoreTests {
    @Test
    func loadBringsTheListAndTheCountTogether() async {
        let store = NotificationsStore(
            notifications: StubNotifications(records: [.unread, .read], unreadCount: 1)
        )

        await store.load()

        #expect(store.state == .loaded([.unread, .read]))
        #expect(store.unreadCount == 1)
    }

    @Test
    func anEmptyInboxLoadsAsAnEmptyList() async {
        let store = NotificationsStore(notifications: StubNotifications())

        await store.load()

        #expect(store.state == .loaded([]))
        #expect(store.unreadCount == 0)
    }

    @Test
    func failureIsReportedAndRetryRecovers() async {
        let notifications = StubNotifications(
            records: [.unread],
            unreadCount: 1,
            failingLoads: 1
        )
        let store = NotificationsStore(notifications: notifications)

        await store.load()
        #expect(store.state == .failed(.offline))

        await store.retry()
        #expect(store.state == .loaded([.unread]))
    }

    @Test
    func markingOneReadMovesTheRowAndTheBadge() async {
        let notifications = StubNotifications(records: [.unread, .read], unreadCount: 1)
        let store = NotificationsStore(notifications: notifications)
        await store.load()

        await store.markRead(id: NotificationRecord.unread.id)

        #expect(store.state.records?.first?.isRead == true)
        #expect(store.unreadCount == 0)
        #expect(await notifications.readIDs == [NotificationRecord.unread.id])
    }

    @Test
    func aRejectedReadPutsTheRowAndTheBadgeBack() async {
        let store = NotificationsStore(
            notifications: StubNotifications(
                records: [.unread],
                unreadCount: 1,
                failingMutations: true
            )
        )
        await store.load()

        await store.markRead(id: NotificationRecord.unread.id)

        #expect(store.state.records?.first?.isRead == false)
        #expect(store.unreadCount == 1)
    }

    @Test
    func markingOneThatIsAlreadyReadSendsNothing() async {
        let notifications = StubNotifications(records: [.read], unreadCount: 0)
        let store = NotificationsStore(notifications: notifications)
        await store.load()

        await store.markRead(id: NotificationRecord.read.id)

        #expect(await notifications.readIDs.isEmpty)
    }

    @Test
    func markingAllReadEmptiesTheBadge() async {
        let notifications = StubNotifications(records: [.unread, .read], unreadCount: 1)
        let store = NotificationsStore(notifications: notifications)
        await store.load()

        await store.markAllRead()

        #expect(store.state.records?.allSatisfy(\.isRead) == true)
        #expect(store.unreadCount == 0)
        #expect(await notifications.markedAll == 1)
    }

    @Test
    func aRejectedMarkAllPutsEverythingBack() async {
        let store = NotificationsStore(
            notifications: StubNotifications(
                records: [.unread, .read],
                unreadCount: 1,
                failingMutations: true
            )
        )
        await store.load()

        await store.markAllRead()

        #expect(store.state.records?.first?.isRead == false)
        #expect(store.unreadCount == 1)
    }

    @Test
    func markingAllWhenNothingIsUnreadSendsNothing() async {
        let notifications = StubNotifications(records: [.read], unreadCount: 0)
        let store = NotificationsStore(notifications: notifications)
        await store.load()

        await store.markAllRead()

        #expect(await notifications.markedAll == 0)
    }

    @Test
    func signingOutDropsAnotherAccountsNotifications() async {
        let store = NotificationsStore(
            notifications: StubNotifications(records: [.unread], unreadCount: 1)
        )
        await store.load()

        store.clear()

        #expect(store.state == .loaded([]))
        #expect(store.unreadCount == 0)
    }
}

private actor StubNotifications: NotificationsProviding {
    private(set) var readIDs: [String] = []
    private(set) var markedAll = 0

    private let records: [NotificationRecord]
    private let count: Int
    private let failingMutations: Bool
    private var failingLoads: Int

    init(
        records: [NotificationRecord] = [],
        unreadCount: Int = 0,
        failingLoads: Int = 0,
        failingMutations: Bool = false
    ) {
        self.records = records
        count = unreadCount
        self.failingLoads = failingLoads
        self.failingMutations = failingMutations
    }

    func notifications() async throws -> [NotificationRecord] {
        if failingLoads > 0 {
            failingLoads -= 1
            throw URLError(.notConnectedToInternet)
        }

        return records
    }

    func unreadNotificationCount() async throws -> Int {
        count
    }

    func markNotificationRead(id: String) async throws -> NotificationRecord {
        readIDs.append(id)
        if failingMutations {
            throw URLError(.notConnectedToInternet)
        }

        return NotificationRecord(.unread, readAt: "2026-01-03T12:00:00.000Z")
    }

    func markAllNotificationsRead() async throws -> Int {
        markedAll += 1
        if failingMutations {
            throw URLError(.notConnectedToInternet)
        }

        return readIDs.count
    }

    func registerDevice(token: String, environment: PushEnvironment) async throws {}

    func unregisterDevice(token: String) async throws {}

    func notificationPreferences() async throws -> NotificationPreferences {
        .init(
            channels: .init(inApp: true, push: false),
            events: .init(releaseDateChanged: true, releaseApproaching: true),
            timingPresets: [.onDay]
        )
    }

    func updateNotificationPreferences(
        _ preferences: NotificationPreferences
    ) async throws -> NotificationPreferences {
        preferences
    }
}

extension NotificationRecord {
    static let unread = NotificationRecord(
        id: "notification-1",
        eventType: .releaseApproaching,
        destinationTitleID: "rawg:274755",
        titleName: "Hades",
        titleArtworkURL: nil,
        message: "Hades arrives in 7 days.",
        subtitle: "Coming soon",
        payload: .releaseApproaching(targetReleaseDate: "2026-01-10"),
        createdAt: "2026-01-03T10:00:00.000Z",
        readAt: nil
    )

    static let read = NotificationRecord(
        id: "notification-2",
        eventType: .releaseDateChanged,
        destinationTitleID: "rawg:3498",
        titleName: "Grand Theft Auto VI",
        titleArtworkURL: nil,
        message: "Grand Theft Auto VI moved to Nov 19, 2026.",
        subtitle: nil,
        payload: .releaseDateChanged(nextReleaseDate: "2026-11-19"),
        createdAt: "2026-01-02T10:00:00.000Z",
        readAt: "2026-01-02T12:00:00.000Z"
    )
}
