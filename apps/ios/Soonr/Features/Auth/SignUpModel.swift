import Foundation
import Observation

enum SignUpField: Hashable, CaseIterable {
    case email
    case username
    case password
    case repeatedPassword
}

@MainActor
@Observable
final class SignUpModel {
    static let minimumPasswordLength = 8

    var email = ""
    var username = ""
    var password = ""
    var repeatedPassword = ""

    private(set) var status: [SignUpField: FieldStatus] = [:]
    private(set) var isSubmitting = false
    /// Form-level only: a rejected sign-up or a failed request. Field problems
    /// live with their field.
    private(set) var failure: FailureReason?

    @ObservationIgnored private let accounts: any AccountCreating
    @ObservationIgnored private let debounceDuration: Duration

    init(accounts: any AccountCreating, debounceDuration: Duration = .milliseconds(350)) {
        self.accounts = accounts
        self.debounceDuration = debounceDuration
    }

    subscript(field: SignUpField) -> FieldStatus {
        status[field] ?? .idle
    }

    /// Called when a field loses focus. Rules are checked on the way out, not
    /// while a value is still being typed.
    func validate(_ field: SignUpField) {
        if let problem = problem(with: field) {
            status[field] = .problem(problem)
            return
        }

        switch field {
        case .email, .username:
            // The availability check owns the verdict for these, so a passing
            // rule must leave it alone. Anything it said about an older value
            // was already retired by `fieldChanged`.
            break
        case .password, .repeatedPassword:
            status[field] = .ok
        }
    }

    /// Returns the first field the user still has to deal with.
    func validateAll() -> SignUpField? {
        SignUpField.allCases.forEach(validate)
        return SignUpField.allCases.first { self[$0].isProblem }
    }

    func checkEmail() async {
        guard email.contains("@") else {
            return
        }

        await check(.email) {
            try await self.accounts.emailAvailability(email: self.email)
        } problem: { _ in
            "An account with this email already exists."
        }
    }

    func checkUsername() async {
        guard username.isEmpty == false, UsernameRule.problem(with: username) == nil else {
            return
        }

        await check(.username) {
            try await self.accounts.usernameAvailability(
                username: UsernameRule.normalize(self.username)
            )
        } problem: { reason in
            switch reason {
            case .reserved: "That username isn't available."
            case .invalid: "That username can't be used."
            case .taken, .unknown, .none: "That username is already taken."
            }
        }
    }

    /// Returns whether the account was created, so the caller can sign in with
    /// the same credentials; sign-up itself issues no session.
    func submit() async -> Bool {
        guard isSubmitting == false else {
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

    /// Typing again retires whatever the field was told, so a message never
    /// describes a value that has since changed.
    func fieldChanged(_ field: SignUpField) {
        status[field] = .idle
        failure = nil
    }

    private func problem(with field: SignUpField) -> String? {
        switch field {
        case .email:
            email.contains("@") ? nil : "Enter an email address you can receive mail at."
        case .username:
            switch UsernameRule.problem(with: username) {
            case .tooLong:
                "Usernames can be at most \(UsernameRule.maximumLength) characters."
            case .malformed:
                "Usernames use letters, numbers, dots and underscores."
            case .none:
                nil
            }
        case .password:
            password.count >= Self.minimumPasswordLength
                ? nil
                : "Use at least \(Self.minimumPasswordLength) characters."
        case .repeatedPassword:
            password == repeatedPassword ? nil : "Those passwords don't match."
        }
    }

    private func check(
        _ field: SignUpField,
        request: @escaping () async throws -> FieldAvailability,
        problem: @escaping (FieldAvailability.Reason?) -> String
    ) async {
        do {
            try await ContinuousClock().sleep(for: debounceDuration)
            try Task.checkCancellation()
            status[field] = .checking

            let availability = try await request()
            try Task.checkCancellation()
            status[field] = availability.available ? .ok : .problem(problem(availability.reason))
        } catch is CancellationError {
            return
        } catch {
            // The server validates again on submit, so a failed check must not
            // stop someone signing up.
            AppLog.auth.error("Availability check failed: \(error)")
            status[field] = .idle
        }
    }
}
