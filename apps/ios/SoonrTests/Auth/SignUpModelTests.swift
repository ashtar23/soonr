import Foundation
import Testing

@testable import Soonr

@MainActor
@Suite(.tags(.networking))
struct SignUpModelTests {
    @Test
    func anAvailableUsernameIsReported() async {
        let model = makeModel(username: .init(available: true, reason: nil))
        model.username = "someone"

        await model.checkUsername()

        #expect(model.usernameAvailability == .available)
    }

    @Test(arguments: [
        (FieldAvailability.Reason.taken, "That username is already taken."),
        (.reserved, "That username isn't available."),
        (.invalid, "That username can't be used."),
    ])
    func aRejectedUsernameExplainsWhy(reason: FieldAvailability.Reason, message: String) async {
        let model = makeModel(username: .init(available: false, reason: reason))
        model.username = "someone"

        await model.checkUsername()

        #expect(model.usernameAvailability == .taken(message))
    }

    /// A malformed username is answered locally, so no request is sent.
    @Test
    func aMalformedUsernameIsNotSentToTheServer() async {
        let accounts = StubAccounts(username: .init(available: true, reason: nil))
        let model = SignUpModel(accounts: accounts, debounceDuration: .zero)
        model.username = "_nope"

        await model.checkUsername()

        #expect(model.usernameProblem == .malformed)
        #expect(model.usernameAvailability == .unchecked)
        #expect(await accounts.usernameChecks.isEmpty)
    }

    @Test
    func theUsernameIsNormalisedBeforeItIsChecked() async {
        let accounts = StubAccounts(username: .init(available: true, reason: nil))
        let model = SignUpModel(accounts: accounts, debounceDuration: .zero)
        model.username = "  SomeOne  "

        await model.checkUsername()

        #expect(await accounts.usernameChecks == ["someone"])
    }

    /// A failed check must not block sign-up: the server validates anyway.
    @Test
    func aFailedCheckDoesNotBlockSubmission() async {
        let model = SignUpModel(accounts: StubAccounts(failing: true), debounceDuration: .zero)
        model.email = "someone@example.com"
        model.username = "someone"
        model.password = "hunter2hunter2"
        model.repeatedPassword = "hunter2hunter2"

        await model.checkUsername()

        #expect(model.usernameAvailability == .indeterminate)
        #expect(model.canSubmit)
    }

    @Test
    func aTakenUsernameBlocksSubmission() async {
        let model = makeModel(username: .init(available: false, reason: .taken))
        model.email = "someone@example.com"
        model.username = "someone"
        model.password = "hunter2hunter2"
        model.repeatedPassword = "hunter2hunter2"

        await model.checkUsername()

        #expect(model.canSubmit == false)
    }

    @Test(arguments: [
        ("someone@example.com", "someone", "hunter2hunter2", "hunter2hunter2", true),
        ("no-at-sign", "someone", "hunter2hunter2", "hunter2hunter2", false),
        ("someone@example.com", "_nope", "hunter2hunter2", "hunter2hunter2", false),
        ("someone@example.com", "someone", "short", "short", false),
        ("someone@example.com", "someone", "hunter2hunter2", "hunter2hunter3", false),
        ("someone@example.com", "someone", "hunter2hunter2", "", false),
    ])
    func submissionRequiresEveryField(
        email: String,
        username: String,
        password: String,
        repeated: String,
        expected: Bool
    ) {
        let model = makeModel(username: .init(available: true, reason: nil))
        model.email = email
        model.username = username
        model.password = password
        model.repeatedPassword = repeated

        #expect(model.canSubmit == expected)
    }

    /// Repeat-password exists because there is no password reset: a typo would
    /// lock the account for good.
    @Test
    func mismatchedPasswordsAreReportedBeforeSubmitting() {
        let model = makeModel(username: .init(available: true, reason: nil))
        model.password = "hunter2hunter2"
        model.repeatedPassword = "hunter2hunter3"

        #expect(model.passwordsMatch == false)
    }

    @Test
    func submittingCreatesTheAccountWithANormalisedUsername() async {
        let accounts = StubAccounts(username: .init(available: true, reason: nil))
        let model = SignUpModel(accounts: accounts, debounceDuration: .zero)
        model.email = "someone@example.com"
        model.username = "SomeOne"
        model.password = "hunter2hunter2"
        model.repeatedPassword = "hunter2hunter2"

        let created = await model.submit()

        #expect(created)
        #expect(model.failure == nil)
        #expect(
            await accounts.signUps == [
                .init(email: "someone@example.com", password: "hunter2hunter2", username: "someone")
            ]
        )
    }

    @Test
    func aConflictIsReportedAndNothingIsCreated() async {
        let accounts = StubAccounts(
            username: .init(available: true, reason: nil),
            signUpFailure: .conflict("An account with this email already exists.")
        )
        let model = SignUpModel(accounts: accounts, debounceDuration: .zero)
        model.email = "someone@example.com"
        model.username = "someone"
        model.password = "hunter2hunter2"
        model.repeatedPassword = "hunter2hunter2"

        let created = await model.submit()

        #expect(created == false)
        #expect(
            model.failure == .server(message: "An account with this email already exists.")
        )
    }

    @Test
    func anIncompleteFormSendsNothing() async {
        let accounts = StubAccounts(username: .init(available: true, reason: nil))
        let model = SignUpModel(accounts: accounts, debounceDuration: .zero)
        model.email = "someone@example.com"

        let created = await model.submit()

        #expect(created == false)
        #expect(await accounts.signUps.isEmpty)
    }

    private func makeModel(username: FieldAvailability) -> SignUpModel {
        SignUpModel(accounts: StubAccounts(username: username), debounceDuration: .zero)
    }
}

private actor StubAccounts: AccountCreating {
    struct SignUpCall: Equatable {
        let email: String
        let password: String
        let username: String
    }

    private(set) var usernameChecks: [String] = []
    private(set) var signUps: [SignUpCall] = []

    private let username: FieldAvailability
    private let failing: Bool
    private let signUpFailure: SignUpFailure?

    init(
        username: FieldAvailability = .init(available: true, reason: nil),
        failing: Bool = false,
        signUpFailure: SignUpFailure? = nil
    ) {
        self.username = username
        self.failing = failing
        self.signUpFailure = signUpFailure
    }

    func emailAvailability(email: String) async throws -> FieldAvailability {
        try failIfNeeded()
        return FieldAvailability(available: true, reason: nil)
    }

    func usernameAvailability(username: String) async throws -> FieldAvailability {
        usernameChecks.append(username)
        try failIfNeeded()
        return self.username
    }

    func signUp(email: String, password: String, username: String) async throws {
        signUps.append(SignUpCall(email: email, password: password, username: username))
        if let signUpFailure {
            throw signUpFailure
        }
    }

    private func failIfNeeded() throws {
        if failing {
            throw URLError(.notConnectedToInternet)
        }
    }
}
