import Foundation
import Observation

enum ProfileState: Equatable {
    case loading
    case loaded(UserProfile)
    case failed(FailureReason)

    var profile: UserProfile? {
        if case let .loaded(profile) = self {
            return profile
        }

        return nil
    }
}

/// The signed-in account's own profile.
///
/// Saved on a button rather than as it is typed, unlike the notification
/// preferences beside it. A username is not a switch: it can be refused, by a
/// rule or by somebody else already having it, and a field that saves itself
/// leaves nowhere for the refusal to land.
@MainActor
@Observable
final class ProfileStore {
    private(set) var state: ProfileState = .loading
    private(set) var isSaving = false
    /// Set when the server refused, and cleared by the next attempt. Held
    /// beside the form rather than replacing it, so nothing typed is lost.
    private(set) var saveFailure: FailureReason?

    @ObservationIgnored private let profiles: any ProfileEditing
    @ObservationIgnored private let visibilityDelay: Duration
    /// The last copy the server acknowledged, which is where a refused
    /// visibility change returns to.
    @ObservationIgnored private var confirmed: UserProfile?
    @ObservationIgnored private var visibilityTask: Task<Void, Never>?

    init(profiles: any ProfileEditing, visibilityDelay: Duration = .milliseconds(400)) {
        self.profiles = profiles
        self.visibilityDelay = visibilityDelay
    }

    func load(userID: String) async {
        if case .loaded = state {
            return
        }

        await fetch(userID: userID)
    }

    func retry(userID: String) async {
        await fetch(userID: userID)
    }

    /// Drops one account's profile rather than showing it to the next.
    func clear() {
        visibilityTask?.cancel()
        visibilityTask = nil
        confirmed = nil
        state = .loading
        saveFailure = nil
        isSaving = false
    }

    /// Answers immediately and saves behind you, unlike the editor beside it.
    ///
    /// Picking from three options is not typing a username: there is nothing
    /// here the server can refuse on a rule, so waiting on a round trip only
    /// makes the control feel broken. A burst of taps sends one request for
    /// whatever you settled on, and a refusal puts the choice back.
    func setWatchlistVisibility(_ visibility: WatchlistVisibility) {
        guard let current = state.profile, current.watchlistVisibility != visibility else {
            return
        }

        state = .loaded(current.setting(watchlistVisibility: visibility))

        visibilityTask?.cancel()
        visibilityTask = Task { [weak self, visibilityDelay] in
            try? await Task.sleep(for: visibilityDelay)
            guard Task.isCancelled == false else {
                return
            }

            await self?.saveVisibility()
        }
    }

    /// Sends a pending change now rather than on the timer, so leaving the
    /// screen straight after a tap does not lose it.
    func flushWatchlistVisibility() async {
        guard visibilityTask != nil else {
            return
        }

        visibilityTask?.cancel()
        await saveVisibility()
    }

    /// Returns whether it was kept, so the screen knows to stop editing.
    @discardableResult
    func save(_ edit: ProfileEdit) async -> Bool {
        guard isSaving == false else {
            return false
        }

        isSaving = true
        saveFailure = nil
        defer { isSaving = false }

        do {
            let saved = try await profiles.updateProfile(edit)
            confirmed = saved
            state = .loaded(saved)
            return true
        } catch is CancellationError {
            return false
        } catch {
            AppLog.auth.error("Could not save the profile: \(error)")
            // What the server said, which for a refused username is the only
            // explanation worth showing: the rule it broke, or that it is
            // taken.
            saveFailure = FailureReason(error)
            return false
        }
    }

    func clearSaveFailure() {
        saveFailure = nil
    }

    private func saveVisibility() async {
        visibilityTask = nil
        guard let pending = state.profile else {
            return
        }

        do {
            let acknowledged = try await profiles.updateProfile(ProfileEdit(from: pending))
            // Another tap may have landed while this was in flight; adopting
            // the server's answer then would undo it.
            if state.profile == pending {
                confirmed = acknowledged
                state = .loaded(acknowledged)
            }
        } catch is CancellationError {
            return
        } catch {
            AppLog.auth.error("Could not save the watchlist visibility: \(error)")
            saveFailure = FailureReason(error)
            if let confirmed {
                state = .loaded(confirmed)
            }
        }
    }

    private func fetch(userID: String) async {
        state = .loading

        do {
            let profile = try await profiles.profile(userID: userID)
            try Task.checkCancellation()
            confirmed = profile
            state = .loaded(profile)
        } catch is CancellationError {
            return
        } catch {
            AppLog.auth.error("Could not load the profile: \(error)")
            state = .failed(FailureReason(error))
        }
    }
}
