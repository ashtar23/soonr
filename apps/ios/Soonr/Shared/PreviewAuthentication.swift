import Foundation

/// In-memory authentication for previews. Performs no network requests.
struct PreviewAuthentication: Authenticating {
    var restored: UserSession?
    var signInResult: Result<UserSession, PreviewAuthenticationError> = .success(.preview)

    func restoreSession() async -> UserSession? {
        restored
    }

    func accessToken() async -> String? {
        restored?.accessToken
    }

    func signIn(email: String, password: String) async throws -> UserSession {
        try signInResult.get()
    }

    func signOut() async throws {}
}

enum PreviewAuthenticationError: Error, LocalizedError, Sendable {
    case invalidCredentials

    var errorDescription: String? {
        "Those credentials didn't work."
    }
}

extension UserSession {
    static let preview = UserSession(
        userID: "00000000-0000-0000-0000-000000000000",
        email: "player@soonr.app",
        accessToken: "preview-token"
    )
}
