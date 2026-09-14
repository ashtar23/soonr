import Foundation
import Testing

@testable import Soonr

@MainActor
@Suite(.tags(.networking))
struct UsernameAvailabilityTests {
    @Test
    func afreeUsernameIsReportedAsFree() async {
        let accounts = StubAvailability(.init(available: true, reason: nil))
        let availability = UsernameAvailability(accounts: accounts, debounceDuration: .zero)

        await availability.check("newname", owned: "reader")

        #expect(availability.status == .ok)
    }

    /// Worded as sign-up words it, because it is the same question about the
    /// same name.
    @Test(arguments: [
        (FieldAvailability.Reason.taken, "That username is already taken."),
        (.reserved, "That username isn't available."),
        (.invalid, "That username can't be used."),
    ])
    func aTakenUsernameExplainsWhy(reason: FieldAvailability.Reason, message: String) async {
        let accounts = StubAvailability(.init(available: false, reason: reason))
        let availability = UsernameAvailability(accounts: accounts, debounceDuration: .zero)

        await availability.check("newname", owned: "reader")

        #expect(availability.status == .problem(message))
    }

    /// The reason this is not sign-up's check: the endpoint does not know who
    /// is asking, so it would call your own name taken.
    @Test(arguments: ["reader", "Reader", "  READER  "])
    func theNameYouAlreadyHaveIsNeverSent(typed: String) async {
        let accounts = StubAvailability(.init(available: false, reason: .taken))
        let availability = UsernameAvailability(accounts: accounts, debounceDuration: .zero)

        await availability.check(typed, owned: "reader")

        #expect(availability.status == .idle)
        #expect(await accounts.checked.isEmpty)
    }

    @Test
    func anAccountWithoutAUsernameHasEveryNameChecked() async {
        let accounts = StubAvailability(.init(available: true, reason: nil))
        let availability = UsernameAvailability(accounts: accounts, debounceDuration: .zero)

        await availability.check("reader", owned: nil)

        #expect(await accounts.checked == ["reader"])
    }

    @Test
    func theUsernameIsNormalisedBeforeItIsSent() async {
        let accounts = StubAvailability(.init(available: true, reason: nil))
        let availability = UsernameAvailability(accounts: accounts, debounceDuration: .zero)

        await availability.check("  NewName  ", owned: "reader")

        #expect(await accounts.checked == ["newname"])
    }

    @Test
    func amalformedUsernameIsExplainedWithoutAskingTheServer() async {
        let accounts = StubAvailability(.init(available: true, reason: nil))
        let availability = UsernameAvailability(accounts: accounts, debounceDuration: .zero)

        await availability.check("_nope", owned: "reader")

        #expect(
            availability.status == .problem("Usernames use letters, numbers, dots and underscores.")
        )
        #expect(await accounts.checked.isEmpty)
    }

    @Test
    func anEmptyFieldHasNothingToSay() async {
        let accounts = StubAvailability(.init(available: true, reason: nil))
        let availability = UsernameAvailability(accounts: accounts, debounceDuration: .zero)

        await availability.check("", owned: nil)

        #expect(availability.status == .idle)
        #expect(await accounts.checked.isEmpty)
    }

    /// Saving asks the database anyway, so a failed check must not leave a
    /// problem that blocks it.
    @Test
    func afailedCheckLeavesNothingInTheWay() async {
        let accounts = StubAvailability(.init(available: true, reason: nil), failing: true)
        let availability = UsernameAvailability(accounts: accounts, debounceDuration: .zero)

        await availability.check("newname", owned: "reader")

        #expect(availability.status == .idle)
    }

    /// Typing back to your own name must clear a "taken" left by the name
    /// before it, rather than keep blocking Save.
    @Test
    func goingBackToYourOwnNameClearsAnEarlierVerdict() async {
        let accounts = StubAvailability(.init(available: false, reason: .taken))
        let availability = UsernameAvailability(accounts: accounts, debounceDuration: .zero)
        await availability.check("someoneelse", owned: "reader")
        #expect(availability.status.isProblem)

        await availability.check("reader", owned: "reader")

        #expect(availability.status == .idle)
    }
}

private actor StubAvailability: AccountCreating {
    private(set) var checked: [String] = []

    private let answer: FieldAvailability
    private let failing: Bool

    init(_ answer: FieldAvailability, failing: Bool = false) {
        self.answer = answer
        self.failing = failing
    }

    func emailAvailability(email _: String) async throws -> FieldAvailability {
        answer
    }

    func usernameAvailability(username: String) async throws -> FieldAvailability {
        checked.append(username)

        if failing {
            throw URLError(.notConnectedToInternet)
        }

        return answer
    }

    func signUp(email _: String, password _: String, username _: String) async throws {}
}
