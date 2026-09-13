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

    @ObservationIgnored private let notifications: any NotificationsProviding

    init(notifications: any NotificationsProviding) {
        self.notifications = notifications
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
        state = .loaded([])
        unreadCount = 0
    }

    /// Moves the row and the badge first, putting both back if the server
    /// refuses.
    func markRead(id: String) async {
        guard let records = state.records,
            let index = records.firstIndex(where: { $0.id == id }),
            records[index].isRead == false
        else {
            return
        }

        let previousState = state
        let previousCount = unreadCount
        state = .loaded(records.replacing(at: index) { $0.markedRead() })
        unreadCount = max(0, unreadCount - 1)

        do {
            let updated = try await notifications.markNotificationRead(id: id)
            if let current = state.records, let index = current.firstIndex(where: { $0.id == id }) {
                state = .loaded(current.replacing(at: index) { _ in updated })
            }
        } catch is CancellationError {
            state = previousState
            unreadCount = previousCount
        } catch {
            AppLog.notifications.error("Could not mark a notification read: \(error)")
            state = previousState
            unreadCount = previousCount
        }
    }

    func markAllRead() async {
        guard let records = state.records, records.contains(where: { $0.isRead == false }) else {
            return
        }

        let previousState = state
        let previousCount = unreadCount
        state = .loaded(records.map { $0.markedRead() })
        unreadCount = 0

        do {
            _ = try await notifications.markAllNotificationsRead()
        } catch is CancellationError {
            state = previousState
            unreadCount = previousCount
        } catch {
            AppLog.notifications.error("Could not mark notifications read: \(error)")
            state = previousState
            unreadCount = previousCount
        }
    }

    private func fetch(showingLoadingState: Bool) async {
        if showingLoadingState {
            state = .loading
        }

        do {
            async let records = notifications.notifications()
            async let count = notifications.unreadNotificationCount()
            let (loaded, unread) = try await (records, count)
            try Task.checkCancellation()
            state = .loaded(loaded)
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

private extension Array {
    func replacing(at index: Int, with transform: (Element) -> Element) -> [Element] {
        var copy = self
        copy[index] = transform(copy[index])
        return copy
    }
}
