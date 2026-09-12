import Foundation

/// Used when the build has no Supabase settings, which happens on a fresh
/// clone and in CI. Browsing works; signing in explains what is missing
/// instead of failing obscurely.
struct UnconfiguredAuthentication: Authenticating {
    func restoreSession() async -> UserSession? {
        nil
    }

    func accessToken() async -> String? {
        nil
    }

    func signIn(email: String, password: String) async throws -> UserSession {
        throw UnconfiguredAuthenticationError.missingConfiguration
    }

    func signOut() async throws {}
}

enum UnconfiguredAuthenticationError: Error, LocalizedError, Sendable {
    case missingConfiguration

    var errorDescription: String? {
        """
        Sign in is unavailable in this build: set SOONR_SUPABASE_PUBLISHABLE_KEY \
        in Configurations/Local.xcconfig.
        """
    }
}
