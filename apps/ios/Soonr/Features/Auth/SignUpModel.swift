import Foundation
import Observation

enum AvailabilityState: Equatable {
    case unchecked
    case checking
    case available
    case taken(String)
    /// The check itself failed. Sign-up is still allowed: the server decides.
    case indeterminate
}

@MainActor
@Observable
final class SignUpModel {
    static let minimumPasswordLength = 8

    var email = ""
    var username = ""
    var password = ""
    var repeatedPassword = ""

    private(set) var emailAvailability: AvailabilityState = .unchecked
    private(set) var usernameAvailability: AvailabilityState = .unchecked
    private(set) var isSubmitting = false
    private(set) var failure: FailureReason?

    @ObservationIgnored private let accounts: any AccountCreating
    @ObservationIgnored private let debounceDuration: Duration

    init(accounts: any AccountCreating, debounceDuration: Duration = .milliseconds(350)) {
        self.accounts = accounts
        self.debounceDuration = debounceDuration
    }

    var usernameProblem: UsernameRule.Problem? {
        username.isEmpty ? nil : UsernameRule.problem(with: username)
    }

    var passwordsMatch: Bool {
        repeatedPassword.isEmpty || password == repeatedPassword
    }

    var canSubmit: Bool {
        email.contains("@")
            && UsernameRule.problem(with: username) == nil
            && password.count >= Self.minimumPasswordLength
            && password == repeatedPassword
            && emailAvailability != .checking
            && usernameAvailability != .checking
            && isTaken(emailAvailability) == false
            && isTaken(usernameAvailability) == false
            && isSubmitting == false
    }

    func checkEmail() async {
        guard email.contains("@") else {
            emailAvailability = .unchecked
            return
        }

        await check(
            setting: { self.emailAvailability = $0 },
            request: { try await self.accounts.emailAvailability(email: self.email) },
            takenMessage: { _ in "An account with this email already exists." }
        )
    }

    func checkUsername() async {
        guard usernameProblem == nil, username.isEmpty == false else {
            usernameAvailability = .unchecked
            return
        }

        await check(
            setting: { self.usernameAvailability = $0 },
            request: {
                try await self.accounts.usernameAvailability(
                    username: UsernameRule.normalize(self.username)
                )
            },
            takenMessage: { reason in
                switch reason {
                case .reserved: "That username isn't available."
                case .invalid: "That username can't be used."
                case .taken, .unknown, .none: "That username is already taken."
                }
            }
        )
    }

    /// Returns whether the account was created, so the caller can sign in with
    /// the same credentials; sign-up itself issues no session.
    func submit() async -> Bool {
        guard canSubmit else {
            return false
        }

        isSubmitting = true
        failure = nil
        defer { isSubmitting = false }

        do {
            try await accounts.signUp(
                email: email,
                password: password,
                username: UsernameRule.normalize(username)
            )
            return true
        } catch is CancellationError {
            return false
        } catch {
            AppLog.auth.error("Sign up failed: \(error)")
            failure = FailureReason(error)
            return false
        }
    }

    func clearFailure() {
        failure = nil
    }

    private func check(
        setting state: @escaping (AvailabilityState) -> Void,
        request: @escaping () async throws -> FieldAvailability,
        takenMessage: @escaping (FieldAvailability.Reason?) -> String
    ) async {
        do {
            try await ContinuousClock().sleep(for: debounceDuration)
            try Task.checkCancellation()
            state(.checking)

            let availability = try await request()
            try Task.checkCancellation()
            state(
                availability.available
                    ? .available
                    : .taken(takenMessage(availability.reason))
            )
        } catch is CancellationError {
            return
        } catch {
            AppLog.auth.error("Availability check failed: \(error)")
            state(.indeterminate)
        }
    }

    private func isTaken(_ state: AvailabilityState) -> Bool {
        if case .taken = state {
            return true
        }

        return false
    }
}
