import Foundation
import Testing

@testable import Soonr

@MainActor
@Suite(.tags(.networking), .timeLimit(.minutes(1)))
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

    // MARK: - Overlapping work

    /// Two reads are two writes. The earlier failing must put back only its
    /// own row, and only its own share of the badge.
    @Test
    func anEarlierFailedReadDoesNotUndoALaterSuccessfulOne() async {
        let notifications = StubNotifications(
            records: [.unread(id: "n1"), .unread(id: "n2")],
            unreadCount: 2,
            failingReadIDs: ["n1"]
        )
        let store = NotificationsStore(notifications: notifications)
        await store.load()
        await notifications.gate.hold("read:n1")

        let failing = Task { await store.markRead(id: "n1") }
        await notifications.gate.waitUntilParked("read:n1")
        await store.markRead(id: "n2")
        await notifications.gate.release("read:n1")
        await failing.value

        #expect(store.state.records?.map(\.isRead) == [false, true])
        #expect(store.unreadCount == 1)
    }

    /// A refusal landing after sign-out must not restore the previous
    /// account's rows and badge onto the next person's screen.
    @Test
    func aReadRefusedAfterSigningOutRestoresNothing() async {
        let notifications = StubNotifications(
            records: [.unread(id: "n1")],
            unreadCount: 1,
            failingReadIDs: ["n1"]
        )
        let store = NotificationsStore(notifications: notifications)
        await store.load()
        await notifications.gate.hold("read:n1")

        let failing = Task { await store.markRead(id: "n1") }
        await notifications.gate.waitUntilParked("read:n1")
        store.clear()
        await notifications.gate.release("read:n1")
        await failing.value

        #expect(store.state == .loaded([]))
        #expect(store.unreadCount == 0)
    }

    /// The badge also counts notifications never paged in, which a refused
    /// mark-all gives back. After sign-out that would be the previous
    /// account's number.
    @Test
    func aMarkAllRefusedAfterSigningOutLeavesTheBadgeAlone() async {
        let notifications = StubNotifications(
            records: [.unread(id: "n1")],
            unreadCount: 5,
            failingMarkAll: true
        )
        let store = NotificationsStore(notifications: notifications)
        await store.load()
        await notifications.gate.hold("all")

        let all = Task { await store.markAllRead() }
        await notifications.gate.waitUntilParked("all")
        store.clear()
        await notifications.gate.release("all")
        await all.value

        #expect(store.unreadCount == 0)
        #expect(store.state == .loaded([]))
    }

    /// A tapped push reads a notification the list may not hold, then asks the
    /// server for the count. That count belongs to whoever tapped it.
    @Test
    func aPushReadFinishingAfterSigningOutLeavesTheBadgeAlone() async {
        let notifications = StubNotifications(records: [], unreadCount: 3)
        let store = NotificationsStore(notifications: notifications)
        await store.load()
        await notifications.gate.hold("read:pushed")

        let reading = Task { await store.markRead(id: "pushed") }
        await notifications.gate.waitUntilParked("read:pushed")
        store.clear()
        await notifications.gate.release("read:pushed")
        await reading.value

        #expect(store.unreadCount == 0)
    }

    @Test
    func aSuccessfulMarkAllOutlastsAnEarlierFailedRead() async {
        let notifications = StubNotifications(
            records: [.unread(id: "n1"), .unread(id: "n2")],
            unreadCount: 2,
            failingReadIDs: ["n1"],
            markAllResult: 2
        )
        let store = NotificationsStore(notifications: notifications)
        await store.load()
        await notifications.gate.hold("read:n1")

        let failing = Task { await store.markRead(id: "n1") }
        await notifications.gate.waitUntilParked("read:n1")
        await store.markAllRead()
        await notifications.gate.release("read:n1")
        await failing.value

        #expect(store.state.records?.allSatisfy(\.isRead) == true)
        #expect(store.unreadCount == 0)
    }

    /// Both failed, so both rows are unread again — including the one whose
    /// own undo was skipped because mark-all had taken it over.
    @Test
    func aFailedMarkAllStillPutsBackAnEarlierFailedRead() async {
        let notifications = StubNotifications(
            records: [.unread(id: "n1"), .unread(id: "n2")],
            unreadCount: 2,
            failingReadIDs: ["n1"],
            failingMarkAll: true
        )
        let store = NotificationsStore(notifications: notifications)
        await store.load()
        await notifications.gate.hold("read:n1")
        await notifications.gate.hold("all")

        let read = Task { await store.markRead(id: "n1") }
        await notifications.gate.waitUntilParked("read:n1")
        let all = Task { await store.markAllRead() }
        await notifications.gate.waitUntilParked("all")
        await notifications.gate.release("read:n1")
        await read.value
        await notifications.gate.release("all")
        await all.value

        #expect(store.state.records?.map(\.isRead) == [false, false])
        #expect(store.unreadCount == 2)
    }

    /// The server took the single read, so a failed mark-all must not undo it.
    @Test
    func aReadThatSucceedsDuringAFailedMarkAllStaysRead() async {
        let notifications = StubNotifications(
            records: [.unread(id: "n1"), .unread(id: "n2")],
            unreadCount: 2,
            failingMarkAll: true
        )
        let store = NotificationsStore(notifications: notifications)
        await store.load()
        await notifications.gate.hold("read:n1")
        await notifications.gate.hold("all")

        let read = Task { await store.markRead(id: "n1") }
        await notifications.gate.waitUntilParked("read:n1")
        let all = Task { await store.markAllRead() }
        await notifications.gate.waitUntilParked("all")
        await notifications.gate.release("read:n1")
        await read.value
        await notifications.gate.release("all")
        await all.value

        #expect(store.state.records?.map(\.isRead) == [true, false])
        #expect(store.unreadCount == 1)
    }

    /// Cancelled is not refused: backing out of a notification quickly cancels
    /// its read, which may already have reached the server. The row is not
    /// put back on a guess; the list asks the server what is true instead.
    @Test
    func aCancelledReadIsNotRolledBack() async {
        let notifications = StubNotifications(records: [.unread(id: "n1")], unreadCount: 1)
        let store = NotificationsStore(
            notifications: notifications,
            refreshDelay: .milliseconds(50)
        )
        await store.load()
        await notifications.gate.hold("read:n1")

        let reading = Task { await store.markRead(id: "n1") }
        await notifications.gate.waitUntilParked("read:n1")
        reading.cancel()
        await notifications.gate.release("read:n1")
        await reading.value

        #expect(store.state.records?.first?.isRead == true)
        await settle(for: .milliseconds(150))
        #expect(await notifications.loads == 2)
    }

    @Test
    func aPageArrivingAfterTheFilterChangedIsDropped() async {
        let notifications = StubNotifications(
            records: [.unread(id: "n1")],
            unreadCount: 1,
            firstPageCursor: "cursor-2",
            laterPages: [Page(items: [.unread(id: "n9")], nextCursor: nil)]
        )
        let store = NotificationsStore(notifications: notifications)
        await store.load()
        await notifications.gate.hold("page")

        let paging = Task { await store.loadMore() }
        await notifications.gate.waitUntilParked("page")
        await store.setShowsUnreadOnly(true)
        await notifications.gate.release("page")
        await paging.value

        #expect(store.state.records?.map(\.id) == ["n1"])
    }

    @Test
    func aPageArrivingAfterSigningOutIsDropped() async {
        let notifications = StubNotifications(
            records: [.unread(id: "n1")],
            unreadCount: 1,
            firstPageCursor: "cursor-2",
            laterPages: [Page(items: [.unread(id: "n9")], nextCursor: nil)]
        )
        let store = NotificationsStore(notifications: notifications)
        await store.load()
        await notifications.gate.hold("page")

        let paging = Task { await store.loadMore() }
        await notifications.gate.waitUntilParked("page")
        store.clear()
        #expect(store.isLoadingMore == false)
        await notifications.gate.release("page")
        await paging.value

        #expect(store.state == .loaded([]))
    }

    // MARK: - Paging

    @Test
    func theSecondPageIsAppendedBelowTheFirst() async {
        let second = NotificationRecord.unread(id: "notification-9")
        let notifications = StubNotifications(
            records: [.unread],
            unreadCount: 1,
            firstPageCursor: "cursor-2",
            laterPages: [Page(items: [second], nextCursor: nil)]
        )
        let store = NotificationsStore(notifications: notifications)
        await store.load()
        #expect(store.hasMore)

        await store.loadMore()

        #expect(store.state.records?.map(\.id) == ["notification-1", "notification-9"])
        #expect(await notifications.cursorsAsked == [nil, "cursor-2"])
    }

    /// The end of the list is what takes the trigger off screen.
    @Test
    func thereIsNoMoreToLoadOnceTheServerSaysSo() async {
        let notifications = StubNotifications(records: [.unread], unreadCount: 1)
        let store = NotificationsStore(notifications: notifications)

        await store.load()

        #expect(store.hasMore == false)
        await store.loadMore()
        #expect(await notifications.loads == 1)
    }

    @Test
    func nothingIsLoadedBeforeTheFirstPageHasArrived() async {
        let notifications = StubNotifications(records: [.unread], unreadCount: 1)
        let store = NotificationsStore(notifications: notifications)

        #expect(store.hasMore == false)
        await store.loadMore()

        #expect(await notifications.loads == 0)
    }

    /// A fast scroll asks repeatedly; the server should hear it once.
    @Test
    func overlappingRequestsForTheSamePageAreOne() async {
        let notifications = StubNotifications(
            records: [.unread],
            unreadCount: 1,
            firstPageCursor: "cursor-2",
            laterPages: [Page(items: [], nextCursor: "cursor-3")]
        )
        let store = NotificationsStore(notifications: notifications)
        await store.load()

        // Both start before either finishes, which is what a fast scroll does.
        async let first: Void = store.loadMore()
        async let second: Void = store.loadMore()
        async let third: Void = store.loadMore()
        _ = await (first, second, third)

        // One first page, one second page.
        #expect(await notifications.loads == 2)
    }

    /// A page that fails leaves the rows already on screen alone: reaching the
    /// bottom again is the retry.
    @Test
    func afailedPageKeepsWhatIsAlreadyLoaded() async {
        let notifications = StubNotifications(
            records: [.unread],
            unreadCount: 1,
            failingLoads: 0,
            firstPageCursor: "cursor-2"
        )
        let store = NotificationsStore(notifications: notifications)
        await store.load()
        await notifications.failNextLoad()

        await store.loadMore()

        #expect(store.state.records?.map(\.id) == ["notification-1"])
        #expect(store.hasMore)
    }

    /// The reason paging and realtime had to be designed together: answering a
    /// change must not discard the pages already scrolled through.
    @Test
    func achangeFromElsewhereKeepsLoadedPagesAndPutsTheNewRowOnTop() async throws {
        let older = NotificationRecord.unread(id: "notification-0")
        let notifications = StubNotifications(
            records: [.unread],
            unreadCount: 1,
            firstPageCursor: "cursor-2",
            laterPages: [Page(items: [older], nextCursor: nil)]
        )
        let store = NotificationsStore(notifications: notifications, refreshDelay: .zero)
        await store.load()
        await store.loadMore()
        #expect(store.state.records?.map(\.id) == ["notification-1", "notification-0"])

        // The server now reports a change, and its first page leads with a new row.
        let arrived = NotificationRecord.unread(id: "notification-2")
        await notifications.setFirstPage([arrived, .unread])
        let loads = await notifications.loadEvents()
        await store.changedRemotely()

        for await _ in loads { break }
        await settle()
        #expect(
            store.state.records?.map(\.id) == [
                "notification-2", "notification-1", "notification-0",
            ]
        )
    }

    // MARK: - Unread only

    /// The server answers a different question, so the pages in hand are
    /// answers to the old one.
    @Test
    func askingForUnreadOnlyAsksTheServerAgainFromTheFirstPage() async {
        let notifications = StubNotifications(
            records: [.unread],
            unreadCount: 1,
            firstPageCursor: "cursor-2"
        )
        let store = NotificationsStore(notifications: notifications)
        await store.load()

        await store.setShowsUnreadOnly(true)

        #expect(store.showsUnreadOnly)
        #expect(await notifications.unreadOnlyAsked == [false, true])
        // From the top, not from the cursor the unfiltered list had reached.
        #expect(await notifications.cursorsAsked == [nil, nil])
    }

    @Test
    func askingForWhatIsAlreadyShowingChangesNothing() async {
        let notifications = StubNotifications(records: [.unread], unreadCount: 1)
        let store = NotificationsStore(notifications: notifications)
        await store.load()

        await store.setShowsUnreadOnly(false)

        #expect(await notifications.loads == 1)
    }

    /// A later page has to keep asking the narrower question, or paging would
    /// widen the list halfway down.
    /// Merging keeps rows the server no longer lists, which is right for the
    /// whole list and wrong here: missing from an unread-only answer means read
    /// somewhere else. Kept, it sat in the list still marked unread while the
    /// badge had already dropped.
    @Test
    func anUnreadOnlyRefreshDropsARowReadElsewhere() async throws {
        let notifications = StubNotifications(
            records: [.unread(id: "n1"), .unread(id: "n2")],
            unreadCount: 2
        )
        let store = NotificationsStore(notifications: notifications, refreshDelay: .zero)
        await store.setShowsUnreadOnly(true)
        #expect(store.state.records?.map(\.id) == ["n1", "n2"])

        await notifications.setFirstPage([.unread(id: "n2")])
        await notifications.setUnreadCount(1)
        let loads = await notifications.loadEvents()
        await store.changedRemotely()
        for await _ in loads { break }
        await settle()

        #expect(store.state.records?.map(\.id) == ["n2"])
        #expect(store.unreadCount == 1)
    }

    @Test
    func alaterPageKeepsTheFilter() async {
        let notifications = StubNotifications(
            records: [.unread],
            unreadCount: 1,
            firstPageCursor: "cursor-2",
            laterPages: [Page(items: [], nextCursor: nil)]
        )
        let store = NotificationsStore(notifications: notifications)
        await store.load()
        await store.setShowsUnreadOnly(true)

        await store.loadMore()

        #expect(await notifications.unreadOnlyAsked == [false, true, true])
    }

    /// Signing out must not leave the next account looking at a filtered list
    /// with no way to tell why it is short.
    @Test
    func signingOutForgetsTheFilter() async {
        let notifications = StubNotifications(records: [.unread], unreadCount: 1)
        let store = NotificationsStore(notifications: notifications)
        await store.load()
        await store.setShowsUnreadOnly(true)

        store.clear()

        #expect(store.showsUnreadOnly == false)
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

    private var records: [NotificationRecord]
    private var count: Int
    private let failingMutations: Bool
    private let failingReadIDs: Set<String>
    private let failingMarkAll: Bool
    /// Requests park here under `read:<id>`, `all`, `first` and `page`.
    let gate = TestGate()
    private let markAllResult: Int
    /// Pages served in order for cursored requests; the first page still comes
    /// from `records`.
    private var laterPages: [Page<NotificationRecord>]
    private(set) var cursorsAsked: [String?] = []
    private(set) var unreadOnlyAsked: [Bool] = []
    private(set) var aboutAsked: [String] = []
    private var aboutResult: [NotificationRecord]?
    private var firstPageCursor: String?
    private var failingLoads: Int
    private var loadSignal: AsyncStream<Void>.Continuation?

    init(
        records: [NotificationRecord] = [],
        unreadCount: Int = 0,
        failingLoads: Int = 0,
        failingMutations: Bool = false,
        failingReadIDs: Set<String> = [],
        failingMarkAll: Bool = false,
        markAllResult: Int = 0,
        firstPageCursor: String? = nil,
        laterPages: [Page<NotificationRecord>] = []
    ) {
        self.firstPageCursor = firstPageCursor
        self.laterPages = laterPages
        self.records = records
        count = unreadCount
        self.failingLoads = failingLoads
        self.failingMutations = failingMutations
        self.failingReadIDs = failingReadIDs
        self.failingMarkAll = failingMarkAll
        self.markAllResult = markAllResult
    }

    /// Yields once per list fetch, so a test can await the fetch it expects
    /// instead of polling for it.
    func loadEvents() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        loadSignal = continuation
        return stream
    }

    func notifications(
        after cursor: String?,
        unreadOnly: Bool
    ) async throws -> Page<NotificationRecord> {
        loads += 1
        cursorsAsked.append(cursor)
        unreadOnlyAsked.append(unreadOnly)
        loadSignal?.yield()
        await gate.pass(cursor == nil ? "first" : "page")

        if failingLoads > 0 {
            failingLoads -= 1
            throw URLError(.notConnectedToInternet)
        }

        if cursor != nil, laterPages.isEmpty == false {
            return laterPages.removeFirst()
        }

        return Page(items: records, nextCursor: firstPageCursor)
    }

    func serveAbout(_ records: [NotificationRecord]) {
        aboutResult = records
    }

    func serveNext(_ page: Page<NotificationRecord>) {
        laterPages.append(page)
    }

    func failNextLoad() {
        failingLoads += 1
    }

    func setFirstPage(_ replacement: [NotificationRecord]) {
        records = replacement
    }

    func notifications(about titleID: String) async throws -> [NotificationRecord] {
        aboutAsked.append(titleID)
        return aboutResult ?? records
    }

    func unreadNotificationCount() async throws -> Int {
        count
    }

    func setUnreadCount(_ replacement: Int) {
        count = replacement
    }

    func markNotificationRead(id: String) async throws -> NotificationRecord {
        readIDs.append(id)
        await gate.pass("read:\(id)")

        // What URLSession does when the task asking is cancelled mid-request.
        if Task.isCancelled {
            throw CancellationError()
        }

        if failingMutations || failingReadIDs.contains(id) {
            throw URLError(.notConnectedToInternet)
        }

        let record = records.first { $0.id == id } ?? .unread(id: id)
        return NotificationRecord(record, readAt: "2026-01-03T12:00:00.000Z")
    }

    func markAllNotificationsRead() async throws -> Int {
        markedAll += 1
        await gate.pass("all")

        if failingMutations || failingMarkAll {
            throw URLError(.notConnectedToInternet)
        }

        return markAllResult
    }

}

extension NotificationRecord {
    /// The same row under another id, for tests about order and identity.
    static func unread(id: String) -> NotificationRecord {
        NotificationRecord(
            id: id,
            eventType: unread.eventType,
            destinationTitleID: unread.destinationTitleID,
            titleName: unread.titleName,
            titleArtworkURL: unread.titleArtworkURL,
            message: unread.message,
            subtitle: unread.subtitle,
            payload: unread.payload,
            createdAt: unread.createdAt,
            readAt: nil
        )
    }

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
