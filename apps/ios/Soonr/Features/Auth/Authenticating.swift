protocol Authenticating: Sendable {
    /// The stored session, refreshed when expired; `nil` when signed out.
    func restoreSession() async -> UserSession?
    func signIn(email: String, password: String) async throws -> UserSession
    func signOut() async throws
}
