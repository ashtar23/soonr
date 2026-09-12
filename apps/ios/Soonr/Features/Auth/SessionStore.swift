import Foundation
import Observation

enum SessionState: Equatable {
    /// Before the stored session has been read, so the UI can avoid flashing
    /// a signed-out state on launch.
    case restoring
    case signedOut
    case signedIn(UserSession)

    var session: UserSession? {
        if case let .signedIn(session) = self {
            return session
        }

        return nil
    }
}

/// App-wide session, created once at the app root and injected through the
/// environment.
@MainActor
@Observable
final class SessionStore {
    private(set) var state: SessionState = .restoring
    private(set) var signInFailure: String?
    private(set) var isSigningIn = false

    @ObservationIgnored private let authentication: any Authenticating

    init(authentication: any Authenticating) {
        self.authentication = authentication
    }

    func restore() async {
        guard case .restoring = state else {
            return
        }

        let session = await authentication.restoreSession()
        state = session.map(SessionState.signedIn) ?? .signedOut
    }

    func signIn(email: String, password: String) async {
        signInFailure = nil
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let session = try await authentication.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            state = .signedIn(session)
        } catch is CancellationError {
            return
        } catch {
            signInFailure =
                error.localizedDescription.isEmpty
                ? "Sign in failed. Please try again."
                : error.localizedDescription
        }
    }

    func signOut() async {
        // Whatever the server says, the app must end up signed out locally.
        try? await authentication.signOut()
        state = .signedOut
        signInFailure = nil
    }

    func clearSignInFailure() {
        signInFailure = nil
    }
}
