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

        #expect(model[.username] == .ok)
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

        #expect(model[.username] == .problem(message))
    }

    @Test
    func aMalformedUsernameIsNotSentToTheServer() async {
        let accounts = StubAccounts()
        let model = SignUpModel(accounts: accounts, debounceDuration: .zero)
        model.username = "_nope"

        await model.checkUsername()

        #expect(await accounts.usernameChecks.isEmpty)
    }

    @Test
    func theUsernameIsNormalisedBeforeItIsChecked() async {
        let accounts = StubAccounts()
        let model = SignUpModel(accounts: accounts, debounceDuration: .zero)
        model.username = "  SomeOne  "

        await model.checkUsername()

        #expect(await accounts.usernameChecks == ["someone"])
    }

    /// The server validates again on submit, so a failed check must not leave
    /// a problem the user cannot clear.
    @Test
    func aFailedCheckLeavesTheFieldWithNothingToSay() async {
        let model = SignUpModel(accounts: StubAccounts(failing: true), debounceDuration: .zero)
        model.username = "someone"

        await model.checkUsername()

        #expect(model[.username] == .idle)
    }

    /// Each field answers for itself; a problem on one never silences another.
    @Test
    func everyUnavailableFieldKeepsItsOwnMessage() async {
        let accounts = StubAccounts(
            email: .init(available: false, reason: .taken),
            username: .init(available: false, reason: .taken)
        )
        let model = SignUpModel(accounts: accounts, debounceDuration: .zero)
        model.email = "taken@example.com"
        model.username = "taken"

        await model.checkEmail()
        await model.checkUsername()

        #expect(model[.email] == .problem("An account with this email already exists."))
        #expect(model[.username] == .problem("That username is already taken."))
    }

    @Test(arguments: [
        (SignUpField.email, "nope", "Enter an email address you can receive mail at."),
        (.username, "_nope", "Usernames use letters, numbers, dots and underscores."),
        (.password, "short", "Use at least 8 characters."),
    ])
    func leavingAnInvalidFieldExplainsIt(
        field: SignUpField,
        value: String,
        message: String
    ) {
        let model = makeModel()
        switch field {
        case .email: model.email = value
        case .username: model.username = value
        case .password: model.password = value
        case .repeatedPassword: break
        }

        model.validate(field)

        #expect(model[field] == .problem(message))
    }

    /// Repeat-password exists because there is no password reset: a typo would
    /// lock the account for good.
    @Test
    func mismatchedPasswordsAreExplainedOnTheRepeatedField() {
        let model = makeModel()
        model.password = "hunter2hunter2"
        model.repeatedPassword = "hunter2hunter3"

        model.validate(.repeatedPassword)

        #expect(model[.repeatedPassword] == .problem("Those passwords don't match."))
    }

    /// Matching but too-short passwords must not look settled.
    @Test
    func aShortPasswordIsAProblemEvenWhenTheRepeatMatches() {
        let model = makeModel()
        model.email = "someone@example.com"
        model.username = "someone"
        model.password = "short"
        model.repeatedPassword = "short"

        #expect(model.validateAll() == .password)
        #expect(model[.password].isProblem)
        #expect(model[.repeatedPassword] == .ok)
    }

    @Test
    func validatingEverythingReportsTheFirstFieldToFix() {
        let model = makeModel()
        model.email = "someone@example.com"
        model.username = "_nope"
        model.password = "hunter2hunter2"
        model.repeatedPassword = "hunter2hunter2"

        #expect(model.validateAll() == .username)
    }

    @Test
    func acompleteFormHasNothingLeftToFix() {
        let model = makeModel()
        fill(model)

        #expect(model.validateAll() == nil)
    }

    /// A check owns the availability verdict, so leaving the field must not
    /// overwrite what the server said.
    @Test
    func leavingAFieldDoesNotClearATakenUsername() async {
        let model = makeModel(username: .init(available: false, reason: .taken))
        model.username = "taken"
        await model.checkUsername()

        model.validate(.username)

        #expect(model[.username] == .problem("That username is already taken."))
    }

    @Test
    func typingAgainRetiresTheMessage() {
        let model = makeModel()
        model.password = "short"
        model.validate(.password)

        model.fieldChanged(.password)

        #expect(model[.password] == .idle)
    }

    @Test
    func submittingCreatesTheAccountWithANormalisedUsername() async {
        let accounts = StubAccounts()
        let model = SignUpModel(accounts: accounts, debounceDuration: .zero)
        fill(model, username: "SomeOne")

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
    func aConflictIsReportedAtFormLevel() async {
        let accounts = StubAccounts(
            signUpFailure: .conflict("An account with this email already exists.")
        )
        let model = SignUpModel(accounts: accounts, debounceDuration: .zero)
        fill(model)

        let created = await model.submit()

        #expect(created == false)
        #expect(model.failure == .server(message: "An account with this email already exists."))
    }

    private func makeModel(
        email: FieldAvailability = .init(available: true, reason: nil),
        username: FieldAvailability = .init(available: true, reason: nil)
    ) -> SignUpModel {
        SignUpModel(
            accounts: StubAccounts(email: email, username: username),
            debounceDuration: .zero
        )
    }

    private func fill(_ model: SignUpModel, username: String = "someone") {
        model.email = "someone@example.com"
        model.username = username
        model.password = "hunter2hunter2"
        model.repeatedPassword = "hunter2hunter2"
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

    private let email: FieldAvailability
    private let username: FieldAvailability
    private let failing: Bool
    private let signUpFailure: SignUpFailure?

    init(
        email: FieldAvailability = .init(available: true, reason: nil),
        username: FieldAvailability = .init(available: true, reason: nil),
        failing: Bool = false,
        signUpFailure: SignUpFailure? = nil
    ) {
        self.email = email
        self.username = username
        self.failing = failing
        self.signUpFailure = signUpFailure
    }

    func emailAvailability(email: String) async throws -> FieldAvailability {
        try failIfNeeded()
        return self.email
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
