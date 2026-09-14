import Foundation
import Observation

/// Whether a username someone is changing to is free, as they type it.
///
/// For a form that edits an existing account rather than creating one, which is
/// the difference that matters: the availability endpoint does not know who is
/// asking, so it reports the name you already have as taken. A name that is
/// still yours is therefore never sent.
@MainActor
@Observable
final class UsernameAvailability {
    private(set) var status: FieldStatus = .idle

    @ObservationIgnored private let accounts: any AccountCreating
    @ObservationIgnored private let debounceDuration: Duration

    init(accounts: any AccountCreating, debounceDuration: Duration = .milliseconds(350)) {
        self.accounts = accounts
        self.debounceDuration = debounceDuration
    }

    /// Meant to be restarted on every keystroke, which cancels the check before
    /// it: only a name typing has paused on reaches the server.
    ///
    /// Rule problems wait out the same pause instead of appearing at once, so a
    /// name is not flagged as malformed for the moment it ends in a dot on its
    /// way to being valid.
    func check(_ username: String, owned: String?) async {
        // Retired first, so a verdict never outlives the name it was about.
        status = .idle

        let normalized = UsernameRule.normalize(username)
        guard normalized.isEmpty == false, normalized != owned.map(UsernameRule.normalize) else {
            return
        }

        do {
            try await ContinuousClock().sleep(for: debounceDuration)
            try Task.checkCancellation()

            if let problem = UsernameRule.problem(with: username) {
                status = .problem(UsernameRule.message(for: problem))
                return
            }

            status = .checking
            let availability = try await accounts.usernameAvailability(username: normalized)
            try Task.checkCancellation()
            status =
                availability.available
                ? .ok
                : .problem(UsernameRule.message(for: availability.reason))
        } catch is CancellationError {
            return
        } catch {
            // Saving asks the database, which is the authority on uniqueness,
            // so a failed check must not stand in the way of it.
            AppLog.auth.error("Username availability check failed: \(error)")
            status = .idle
        }
    }
}
