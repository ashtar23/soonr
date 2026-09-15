import Foundation
import Observation

enum NotificationsState: Equatable {
    case loading
    case loaded([NotificationRecord])
    case failed(FailureReason)

    var records: [NotificationRecord]? {
        if case let .loaded(records) = self {
            return records
        }

        return nil
    }
}

/// Owns the list and the unread count together, because a badge that disagrees
/// with the screen behind it is worse than no badge.
@MainActor
@Observable
final class NotificationsStore {
    private(set) var state: NotificationsState = .loading
    private(set) var unreadCount = 0
    /// True while a further page is on its way, so a fast scroll cannot start
    /// the same request several times over.
    private(set) var isLoadingMore = false
    /// Narrows the list to what has not been read. Held here rather than on the
    /// screen because it changes what is asked for, not what is shown: the
    /// server answers a different question, so the pages already loaded are
    /// answers to the old one and are thrown away.
    private(set) var showsUnreadOnly = false

    var hasMore: Bool {
        state.records != nil && page.hasMore
    }

    @ObservationIgnored private var page = PagedList<NotificationRecord>()

    @ObservationIgnored private let notifications: any NotificationsReading
    @ObservationIgnored private let refreshDelay: Duration
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// How many stream events this device's own writes are still owed.
    ///
    /// The server notifies once per row it changes, so reading a notification
    /// comes straight back as news that notifications changed — news the screen
    /// already acted on. Counting them off is exact rather than approximate:
    /// marking everything read reports how many rows moved, which is how many
    /// events it will produce.
    @ObservationIgnored private var expectedEchoes = 0
    @ObservationIgnored private var echoesExpectedAt: ContinuousClock.Instant?

    /// Rows with a read still out, each under the latest write that touched it
    /// and the copy the server last confirmed.
    ///
    /// This is what lets a failure undo only its own work. A refused write puts
    /// a row back only if no later write has taken it over, and puts it back to
    /// what the server said rather than to whatever the screen showed when the
    /// write began — which may itself have been another write's guess.
    @ObservationIgnored private var pendingReads: [String: PendingRead] = [:]
    @ObservationIgnored private var lastWrite = 0
    /// Moves whenever the count is taken from the server. A write's own share
    /// of the badge is only undone if the count has not been replaced since:
    /// once it has, the server's number already describes the outcome.
    @ObservationIgnored private var countRevision = 0
    /// Moves on sign-out. A write started under an older value belongs to the
    /// previous account, and its answer is dropped.
    @ObservationIgnored private var sessionGeneration = 0
    /// Moves on sign-out and when the filter changes. A page asked for under an
    /// older value answers a question nobody is asking any more.
    @ObservationIgnored private var queryGeneration = 0

    private struct PendingRead {
        let write: Int
        let confirmed: NotificationRecord
    }

    init(
        notifications: any NotificationsReading,
        refreshDelay: Duration = .milliseconds(300)
    ) {
        self.notifications = notifications
        self.refreshDelay = refreshDelay
    }

    func setShowsUnreadOnly(_ showsUnreadOnly: Bool) async {
        guard showsUnreadOnly != self.showsUnreadOnly else {
            return
        }

        self.showsUnreadOnly = showsUnreadOnly
        queryGeneration += 1
        refreshTask?.cancel()
        isLoadingMore = false
        pendingReads = [:]
        page = PagedList<NotificationRecord>()
        await fetch(showingLoadingState: true)
    }

    func load() async {
        await fetch(showingLoadingState: state.records == nil)
    }

    func retry() async {
        await fetch(showingLoadingState: true)
    }

    func refresh() async {
        await fetch(showingLoadingState: false)
    }

    func clear() {
        sessionGeneration += 1
        queryGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        expectedEchoes = 0
        echoesExpectedAt = nil
        pendingReads = [:]
        isLoadingMore = false
        showsUnreadOnly = false
        page = PagedList<NotificationRecord>()
        state = .loaded([])
        unreadCount = 0
    }

    /// The server's news that notifications changed.
    ///
    /// It carries nothing, so answering it means refetching — which is worth
    /// doing only for a change this device did not make. A burst is collapsed
    /// into one refetch, because the trigger fires per row and a single action
    /// on the other end can produce a dozen events that all have the same
    /// answer.
    func changedRemotely() async {
        guard consumeEcho() == false else {
            return
        }

        scheduleReconcile()
    }

    private func scheduleReconcile() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self, refreshDelay] in
            try? await Task.sleep(for: refreshDelay)
            guard Task.isCancelled == false else {
                return
            }

            await self?.reconcile()
        }
    }

    private func consumeEcho() -> Bool {
        guard expectedEchoes > 0, let expectedAt = echoesExpectedAt else {
            return false
        }

        // An event that never arrives would otherwise leave the count standing
        // and swallow the next real change, so it only holds briefly.
        guard ContinuousClock.now - expectedAt < .seconds(10) else {
            expectedEchoes = 0
            echoesExpectedAt = nil
            return false
        }

        expectedEchoes -= 1
        if expectedEchoes == 0 {
            echoesExpectedAt = nil
        }

        return true
    }

    /// Records writes this device made, so the events they cause are not
    /// answered with a refetch of what is already on screen.
    private func expectEchoes(_ count: Int) {
        guard count > 0 else {
            return
        }

        expectedEchoes += count
        echoesExpectedAt = .now
    }

    /// Moves the row and the badge first, putting back only this row and its
    /// share of the badge if the server refuses.
    ///
    /// Returns whether the read stands, so a screen holding its own copy of the
    /// row knows whether to keep it read.
    @discardableResult
    func markRead(id: String) async -> Bool {
        let known = state.records?.first { $0.id == id }

        // Only a record we hold and already know to be read is worth skipping.
        // A tapped push opens this before the list has loaded, and requiring a
        // loaded list here left the server never told.
        if let known, known.isRead {
            return true
        }

        let session = sessionGeneration
        let countedAt = countRevision
        let write = beginWrite()
        if let known {
            hold(known, under: write)
            page.update(known.markedRead())
            publishIfLoaded()
            unreadCount = max(0, unreadCount - 1)
        }

        do {
            let updated = try await notifications.markNotificationRead(id: id)
            guard session == sessionGeneration else {
                return false
            }

            settle(updated, from: write)
            // A count taken from the server while this was out may or may not
            // include it. Not expecting the echo lets that event refetch and
            // settle the number instead of swallowing it.
            if known == nil || countedAt == countRevision {
                expectEchoes(1)
            }

            if known == nil,
                let count = try? await notifications.unreadNotificationCount(),
                session == sessionGeneration
            {
                // Nothing local was adjusted, so the count — and the badge that
                // follows it — would otherwise still include what was just read.
                takeServerCount(count)
            }

            return true
        } catch is CancellationError {
            guard session == sessionGeneration else {
                return false
            }

            // Cancelled is not refused. Backing out of a notification cancels
            // its read, which may already have reached the server, so the row
            // stays read and the server is asked what is true.
            scheduleReconcile()
            return true
        } catch {
            AppLog.notifications.error("Could not mark a notification read: \(error)")
            guard session == sessionGeneration else {
                return false
            }

            undo(write, countedAt: countedAt)
            return false
        }
    }

    /// Everything a collapsed row stands for, because the row is unread when
    /// anything behind it is and clearing it has to mean all of them.
    ///
    /// One request each: the API marks notifications read by id, and a handful
    /// of them is what a group holds.
    func markRead(ids: [String]) async {
        for id in ids {
            await markRead(id: id)
        }
    }

    /// A write over every loaded row, following the same rules as a single
    /// read: it takes over rows already being read, and a failure puts back
    /// only the rows it still owns.
    func markAllRead() async {
        guard let records = state.records, records.contains(where: { $0.isRead == false }) else {
            return
        }

        let session = sessionGeneration
        let countedAt = countRevision
        let write = beginWrite()
        // The badge also counts what has not been paged in, which no row
        // here can give back on failure.
        let unloadedUnread = max(0, unreadCount - records.count { $0.isRead == false })
        for record in page.items where record.isRead == false || pendingReads[record.id] != nil {
            hold(record, under: write)
        }
        page.updateAll { $0.markedRead() }
        publishIfLoaded()
        unreadCount = 0

        do {
            let changed = try await notifications.markAllNotificationsRead()
            guard session == sessionGeneration else {
                return
            }

            for (id, pending) in pendingReads where pending.write == write {
                pendingReads[id] = nil
            }

            // One event per row the server actually changed.
            if countedAt == countRevision {
                expectEchoes(changed)
            }
        } catch is CancellationError {
            guard session == sessionGeneration else {
                return
            }

            scheduleReconcile()
        } catch {
            AppLog.notifications.error("Could not mark notifications read: \(error)")
            guard session == sessionGeneration else {
                return
            }

            undo(write, countedAt: countedAt, unloadedUnread: unloadedUnread)
        }
    }

    private func beginWrite() -> Int {
        lastWrite += 1
        return lastWrite
    }

    /// Hands a row to a write, keeping the copy the server confirmed if an
    /// earlier write already holds one — that earlier write's guess is not
    /// what a failure should return to.
    private func hold(_ record: NotificationRecord, under write: Int) {
        let confirmed = pendingReads[record.id]?.confirmed ?? record
        pendingReads[record.id] = PendingRead(write: write, confirmed: confirmed)
    }

    /// The server took a read. If a later write still owns the row, it keeps
    /// it, but a failure of that write now returns to this answer.
    private func settle(_ confirmed: NotificationRecord, from write: Int) {
        if let pending = pendingReads[confirmed.id] {
            pendingReads[confirmed.id] =
                pending.write == write
                ? nil
                : PendingRead(write: pending.write, confirmed: confirmed)
        }

        page.update(confirmed)
        publishIfLoaded()
    }

    private func undo(_ write: Int, countedAt: Int, unloadedUnread: Int = 0) {
        var restored = 0
        for (id, pending) in pendingReads where pending.write == write {
            pendingReads[id] = nil
            guard page.contains(id: id) else {
                continue
            }

            page.update(pending.confirmed)
            if pending.confirmed.isRead == false {
                restored += 1
            }
        }

        publishIfLoaded()
        if countedAt == countRevision {
            unreadCount += restored + unloadedUnread
        }
    }

    /// Rows the server has just described are its truth, not a write's guess,
    /// so nothing should later be undone back over them.
    private func forgetPendingReads(for records: [NotificationRecord]) {
        for record in records {
            pendingReads[record.id] = nil
        }
    }

    private func takeServerCount(_ count: Int) {
        unreadCount = count
        countRevision += 1
    }

    /// A loading or failed screen is not turned into a list by a write that
    /// happened to finish meanwhile.
    private func publishIfLoaded() {
        guard state.records != nil else {
            return
        }

        state = .loaded(page.items)
    }

    /// Every notification about one game, asked for directly rather than
    /// counted out of the pages in hand.
    func records(about titleID: String) async throws -> [NotificationRecord] {
        try await notifications.notifications(about: titleID)
    }

    /// The next page, asked for when the last row comes into view.
    ///
    /// Silent about failure on purpose: the rows already on screen are still
    /// good, and a scroll that reaches the bottom again retries. A banner over
    /// a working list would be worse than the row that did not arrive.
    func loadMore() async {
        guard isLoadingMore == false, let cursor = page.nextCursor else {
            return
        }

        let asked = queryGeneration
        isLoadingMore = true
        defer {
            if asked == queryGeneration {
                isLoadingMore = false
            }
        }

        do {
            let next = try await notifications.notifications(
                after: cursor,
                unreadOnly: showsUnreadOnly
            )
            try Task.checkCancellation()
            guard asked == queryGeneration else {
                return
            }

            page.append(next)
            publishIfLoaded()
        } catch is CancellationError {
            return
        } catch {
            AppLog.notifications.error("Could not load more notifications: \(error)")
        }
    }

    /// Reloads the first page only, and merges it into the whole list.
    ///
    /// Everything new is newest, so it belongs on the first page; refetching
    /// every page loaded would cost a request each to learn the same thing, and
    /// replacing the list wholesale would throw away the reader's place in it.
    /// The unread filter is the exception, and replaces it.
    private func reconcile() async {
        let asked = queryGeneration
        do {
            async let first = notifications.notifications(
                after: nil,
                unreadOnly: showsUnreadOnly
            )
            async let count = notifications.unreadNotificationCount()
            let (reloaded, unread) = try await (first, count)
            try Task.checkCancellation()
            guard asked == queryGeneration else {
                return
            }

            if showsUnreadOnly {
                // A row missing from an unread-only answer was read somewhere
                // else, so it has to go rather than be kept. Unread lists are
                // short, and starting again from the first page costs less
                // than showing a read notification under an "Unread" filter.
                page.reset(to: reloaded)
                pendingReads = [:]
            } else {
                forgetPendingReads(for: reloaded.items)
                page.reconcileFirstPage(reloaded)
            }

            state = .loaded(page.items)
            takeServerCount(unread)
        } catch is CancellationError {
            return
        } catch {
            AppLog.notifications.error("Could not reconcile notifications: \(error)")
        }
    }

    private func fetch(showingLoadingState: Bool) async {
        let asked = queryGeneration
        if showingLoadingState {
            state = .loading
        }

        do {
            async let first = notifications.notifications(
                after: nil,
                unreadOnly: showsUnreadOnly
            )
            async let count = notifications.unreadNotificationCount()
            let (loaded, unread) = try await (first, count)
            try Task.checkCancellation()
            guard asked == queryGeneration else {
                return
            }

            page.reset(to: loaded)
            pendingReads = [:]
            state = .loaded(page.items)
            takeServerCount(unread)
        } catch is CancellationError {
            return
        } catch {
            guard asked == queryGeneration else {
                return
            }

            AppLog.notifications.error("Could not load notifications: \(error)")
            state = .failed(FailureReason(error))
        }
    }
}

private extension NotificationRecord {
    /// The server sets the real timestamp; this stands in until it answers.
    func markedRead() -> NotificationRecord {
        isRead ? self : NotificationRecord(self, readAt: ISO8601DateFormatter().string(from: .now))
    }
}
