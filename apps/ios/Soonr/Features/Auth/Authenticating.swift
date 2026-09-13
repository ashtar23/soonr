protocol Authenticating: Sendable {
    /// The stored session, refreshed when expired; `nil` when signed out.
    func restoreSession() async -> UserSession?
    /// A currently valid access token for `apps/api`, refreshed if needed.
    /// Read per request rather than cached, because the session refreshes in
    /// the background.
    func accessToken() async -> String?
    /// A token minted now, rather than the one already held. Used after the
    /// server rejects a request, to tell a stale token from a finished
    /// session. `nil` when there is no session left to refresh.
    func refreshedAccessToken() async -> String?
    func signIn(email: String, password: String) async throws -> UserSession
    func signOut() async throws
}
