protocol Authenticating: Sendable {
    /// The stored session, refreshed when expired; `nil` when signed out.
    func restoreSession() async -> UserSession?
    /// A currently valid access token for `apps/api`, refreshed if needed.
    /// Read per request rather than cached, because the session refreshes in
    /// the background.
    func accessToken() async -> String?
    func signIn(email: String, password: String) async throws -> UserSession
    func signOut() async throws
}
