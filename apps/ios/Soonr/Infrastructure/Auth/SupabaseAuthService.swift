import Auth
import Foundation

/// Supabase-backed authentication. The SDK owns token refresh and Keychain
/// persistence, which is the reason it is the project's one dependency.
struct SupabaseAuthService: Authenticating {
    private let client: AuthClient

    init(configuration: SupabaseConfiguration) {
        client = AuthClient(
            configuration: AuthClient.Configuration(
                url: configuration.url.appending(path: "auth/v1"),
                headers: ["apikey": configuration.publishableKey],
                localStorage: AuthClient.Configuration.defaultLocalStorage
            )
        )
    }

    func restoreSession() async -> UserSession? {
        // `session` refreshes an expired session and throws when none exists.
        guard let session = try? await client.session else {
            return nil
        }

        return UserSession(session)
    }

    func signIn(email: String, password: String) async throws -> UserSession {
        UserSession(try await client.signIn(email: email, password: password))
    }

    func signOut() async throws {
        try await client.signOut()
    }
}

private extension UserSession {
    init(_ session: Session) {
        self.init(
            userID: session.user.id.uuidString,
            email: session.user.email,
            accessToken: session.accessToken
        )
    }
}
