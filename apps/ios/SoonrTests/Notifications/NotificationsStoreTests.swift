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

    /// A tapped push opens the app before the list has loaded. Requiring a
    /// loaded list here meant the server was never told, and the notification
    /// stayed unread — while tapping the same row in the list worked.
    @Test
    func markingOneReadBeforeTheListLoadsStillTellsTheServer() async {
        let notifications = StubNotifications(records: [.unread], unreadCount: 1)
        let store = NotificationsStore(notifications: notifications)

        await store.markRead(id: NotificationRecord.unread.id)

        #expect(await notifications.readIDs == [NotificationRecord.unread.id])
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

    // MARK: - Answering the stream

    /// The server notifies on every row it changes, including the one this
    /// device just read, and the screen already shows that.
    @Test
    func aChangeThisDeviceMadeIsNotRefetched() async throws {
        let notifications = StubNotifications(records: [.unread], unreadCount: 1)
        let store = NotificationsStore(notifications: notifications, refreshDelay: .zero)
        await store.load()

        await store.markRead(id: NotificationRecord.unread.id)
        await store.changedRemotely()
        await settle()

        #expect(await notifications.loads == 1)
    }

    /// Marking everything read moves as many rows as were unread, and the
    /// trigger fires once per row.
    @Test
    func markingEverythingReadAbsorbsOneEventPerRow() async throws {
        let notifications = StubNotifications(
            records: [.unread, .read],
            unreadCount: 2,
            markAllResult: 2
        )
        let store = NotificationsStore(notifications: notifications, refreshDelay: .zero)
        await store.load()

        await store.markAllRead()
        await store.changedRemotely()
        await store.changedRemotely()
        await settle()

        #expect(await notifications.loads == 1)
    }

    @Test
    func aChangeFromElsewhereReloadsTheList() async throws {
        let notifications = StubNotifications(records: [.unread], unreadCount: 1)
        let store = NotificationsStore(notifications: notifications, refreshDelay: .zero)
        await store.load()

        let loads = await notifications.loadEvents()
        await store.changedRemotely()

        for await _ in loads { break }
        #expect(await notifications.loads == 2)
    }

    /// A single action on the other end can produce a dozen events with the
    /// same answer, and that answer costs a round trip.
    @Test
    func aBurstOfChangesCostsOneRefetch() async throws {
        let notifications = StubNotifications(records: [.unread], unreadCount: 1)
        let store = NotificationsStore(
            notifications: notifications,
            refreshDelay: .milliseconds(20)
        )
        await store.load()

        let loads = await notifications.loadEvents()
        for _ in 0..<5 {
            await store.changedRemotely()
        }

        for await _ in loads { break }
        await settle()
        #expect(await notifications.loads == 2)
    }

    /// The counts balance: a change from elsewhere landing in the middle of
    /// this device's own burst still costs exactly one refetch.
    @Test
    func aChangeArrivingDuringOurOwnBurstIsStillAnswered() async throws {
        let notifications = StubNotifications(
            records: [.unread],
            unreadCount: 1,
            markAllResult: 2
        )
        let store = NotificationsStore(notifications: notifications, refreshDelay: .zero)
        await store.load()

        await store.markAllRead()
        let loads = await notifications.loadEvents()
        // Two of ours, and one from somewhere else.
        await store.changedRemotely()
        await store.changedRemotely()
        await store.changedRemotely()

        for await _ in loads { break }
        await settle()
        #expect(await notifications.loads == 2)
    }

    @Test
    func signingOutCancelsAPendingRefetch() async throws {
        let notifications = StubNotifications(records: [.unread], unreadCount: 1)
        let store = NotificationsStore(
            notifications: notifications,
            refreshDelay: .milliseconds(50)
        )
        await store.load()

        await store.changedRemotely()
        store.clear()
        await settle(for: .milliseconds(120))

        #expect(await notifications.loads == 1)
    }

    /// Proving something does *not* happen needs a bounded wait; everything
    /// else in this suite awaits the event itself.
    private func settle(for duration: Duration = .milliseconds(60)) async {
        try? await Task.sleep(for: duration)
    }
}

private actor StubNotifications: NotificationsReading {
    private(set) var readIDs: [String] = []
    private(set) var markedAll = 0
    private(set) var loads = 0

    private let records: [NotificationRecord]
    private let count: Int
    private let failingMutations: Bool
    private let markAllResult: Int
    private var failingLoads: Int
    private var loadSignal: AsyncStream<Void>.Continuation?

    init(
        records: [NotificationRecord] = [],
        unreadCount: Int = 0,
        failingLoads: Int = 0,
        failingMutations: Bool = false,
        markAllResult: Int = 0
    ) {
        self.records = records
        count = unreadCount
        self.failingLoads = failingLoads
        self.failingMutations = failingMutations
        self.markAllResult = markAllResult
    }

    /// Yields once per list fetch, so a test can await the fetch it expects
    /// instead of polling for it.
    func loadEvents() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        loadSignal = continuation
        return stream
    }

    func notifications() async throws -> [NotificationRecord] {
        loads += 1
        loadSignal?.yield()

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

        return markAllResult
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
