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

    init(
        notifications: any NotificationsReading,
        refreshDelay: Duration = .milliseconds(300)
    ) {
        self.notifications = notifications
        self.refreshDelay = refreshDelay
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
        refreshTask?.cancel()
        refreshTask = nil
        expectedEchoes = 0
        echoesExpectedAt = nil
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

    /// Moves the row and the badge first, putting both back if the server
    /// refuses.
    func markRead(id: String) async {
        let known = state.records?.firstIndex { $0.id == id }

        // Only a record we hold and already know to be read is worth skipping.
        // A tapped push opens this before the list has loaded, and requiring a
        // loaded list here left the server never told.
        if let records = state.records, let known, records[known].isRead {
            return
        }

        let previousPage = page
        let previousState = state
        let previousCount = unreadCount
        if let records = state.records, let known {
            page.update(records[known].markedRead())
            state = .loaded(page.items)
            unreadCount = max(0, unreadCount - 1)
        }

        do {
            let updated = try await notifications.markNotificationRead(id: id)
            expectEchoes(1)
            page.update(updated)
            state = .loaded(page.items)

            if known == nil {
                // Nothing local was adjusted, so the count — and the badge that
                // follows it — would otherwise still include what was just read.
                unreadCount = (try? await notifications.unreadNotificationCount()) ?? unreadCount
            }
        } catch is CancellationError {
            page = previousPage
            state = previousState
            unreadCount = previousCount
        } catch {
            AppLog.notifications.error("Could not mark a notification read: \(error)")
            page = previousPage
            state = previousState
            unreadCount = previousCount
        }
    }

    func markAllRead() async {
        guard let records = state.records, records.contains(where: { $0.isRead == false }) else {
            return
        }

        let previousPage = page
        let previousState = state
        let previousCount = unreadCount
        page.updateAll { $0.markedRead() }
        state = .loaded(page.items)
        unreadCount = 0

        do {
            // One event per row the server actually changed.
            expectEchoes(try await notifications.markAllNotificationsRead())
        } catch is CancellationError {
            page = previousPage
            state = previousState
            unreadCount = previousCount
        } catch {
            AppLog.notifications.error("Could not mark notifications read: \(error)")
            page = previousPage
            state = previousState
            unreadCount = previousCount
        }
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

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let next = try await notifications.notifications(after: cursor)
            try Task.checkCancellation()
            page.append(next)
            state = .loaded(page.items)
        } catch is CancellationError {
            return
        } catch {
            AppLog.notifications.error("Could not load more notifications: \(error)")
        }
    }

    /// Reloads the first page only, and merges it.
    ///
    /// Everything new is newest, so it belongs on the first page; refetching
    /// every page loaded would cost a request each to learn the same thing, and
    /// replacing the list wholesale would throw away the reader's place in it.
    private func reconcile() async {
        do {
            async let first = notifications.notifications(after: nil)
            async let count = notifications.unreadNotificationCount()
            let (reloaded, unread) = try await (first, count)
            try Task.checkCancellation()
            page.reconcileFirstPage(reloaded)
            state = .loaded(page.items)
            unreadCount = unread
        } catch is CancellationError {
            return
        } catch {
            AppLog.notifications.error("Could not reconcile notifications: \(error)")
        }
    }

    private func fetch(showingLoadingState: Bool) async {
        if showingLoadingState {
            state = .loading
        }

        do {
            async let first = notifications.notifications(after: nil)
            async let count = notifications.unreadNotificationCount()
            let (loaded, unread) = try await (first, count)
            try Task.checkCancellation()
            page.reset(to: loaded)
            state = .loaded(page.items)
            unreadCount = unread
        } catch is CancellationError {
            return
        } catch {
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
