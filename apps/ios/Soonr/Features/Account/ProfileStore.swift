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

    init(profiles: any ProfileEditing) {
        self.profiles = profiles
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
        state = .loading
        saveFailure = nil
        isSaving = false
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

    private func fetch(userID: String) async {
        state = .loading

        do {
            let profile = try await profiles.profile(userID: userID)
            try Task.checkCancellation()
            state = .loaded(profile)
        } catch is CancellationError {
            return
        } catch {
            AppLog.auth.error("Could not load the profile: \(error)")
            state = .failed(FailureReason(error))
        }
    }
}
