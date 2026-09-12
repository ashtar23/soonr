import SwiftUI

/// Sign-up is reached from a sheet that three different screens present, none
/// of which otherwise needs this capability, so it travels in the environment
/// rather than through each of them.
private struct AccountCreatingKey: EnvironmentKey {
    static let defaultValue: any AccountCreating = UnconfiguredAccountCreation()
}

extension EnvironmentValues {
    var accounts: any AccountCreating {
        get { self[AccountCreatingKey.self] }
        set { self[AccountCreatingKey.self] = newValue }
    }
}

private struct UnconfiguredAccountCreation: AccountCreating {
    func emailAvailability(email: String) async throws -> FieldAvailability {
        FieldAvailability(available: true, reason: nil)
    }

    func usernameAvailability(username: String) async throws -> FieldAvailability {
        FieldAvailability(available: true, reason: nil)
    }

    func signUp(email: String, password: String, username: String) async throws {
        throw SignUpFailure.invalid("Account creation isn't available in this build.")
    }
}
