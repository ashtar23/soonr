import Foundation
import Observation

enum NotificationPreferencesState: Equatable {
    case loading
    case loaded(NotificationPreferences)
    case failed(FailureReason)

    var preferences: NotificationPreferences? {
        if case let .loaded(preferences) = self {
            return preferences
        }

        return nil
    }
}

/// Switches answer immediately and the save follows, because one that waits
/// for a round trip feels broken. A rejected save puts the screen back to what
/// the server last confirmed.
@MainActor
@Observable
final class NotificationPreferencesStore {
    private(set) var state: NotificationPreferencesState = .loading
    private(set) var saveFailure: FailureReason?

    @ObservationIgnored private let notifications: any NotificationPreferencesProviding
    @ObservationIgnored private let saveDelay: Duration
    /// The last copy the server acknowledged, which is where a failed save
    /// returns to.
    @ObservationIgnored private var confirmed: NotificationPreferences?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(
        notifications: any NotificationPreferencesProviding,
        saveDelay: Duration = .milliseconds(400)
    ) {
        self.notifications = notifications
        self.saveDelay = saveDelay
    }

    var preferences: NotificationPreferences? {
        state.preferences
    }

    func load() async {
        if case .loaded = state {
            return
        }

        await fetch()
    }

    func retry() async {
        await fetch()
    }

    func edit(_ change: (inout NotificationPreferences) -> Void) {
        guard var edited = preferences else {
            return
        }

        change(&edited)
        state = .loaded(edited)
        scheduleSave()
    }

    /// Sends a pending change now instead of on the timer, so leaving the
    /// screen straight after a tap does not lose it.
    func flush() async {
        guard saveTask != nil else {
            return
        }

        saveTask?.cancel()
        await save()
    }

    func clearSaveFailure() {
        saveFailure = nil
    }

    /// Drops one account's settings rather than showing them to the next.
    func clear() {
        saveTask?.cancel()
        saveTask = nil
        confirmed = nil
        saveFailure = nil
        state = .loading
    }

    private func fetch() async {
        state = .loading

        do {
            let loaded = try await notifications.notificationPreferences()
            try Task.checkCancellation()
            confirmed = loaded
            state = .loaded(loaded)
        } catch is CancellationError {
            return
        } catch {
            AppLog.notifications.error("Could not load notification preferences: \(error)")
            state = .failed(FailureReason(error))
        }
    }

    /// Restarting the timer on each change sends one request for a burst of
    /// taps rather than one per switch.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self, saveDelay] in
            try? await Task.sleep(for: saveDelay)
            guard Task.isCancelled == false else {
                return
            }

            await self?.save()
        }
    }

    private func save() async {
        saveTask = nil
        guard let pending = preferences else {
            return
        }

        do {
            let acknowledged = try await notifications.updateNotificationPreferences(pending)
            // Another switch may have moved while this was in flight; adopting
            // the server's answer then would undo it.
            if preferences == pending {
                confirmed = acknowledged
                state = .loaded(acknowledged)
            }
        } catch is CancellationError {
            return
        } catch {
            AppLog.notifications.error("Could not save notification preferences: \(error)")
            saveFailure = FailureReason(error)
            if let confirmed {
                state = .loaded(confirmed)
            }
        }
    }
}
