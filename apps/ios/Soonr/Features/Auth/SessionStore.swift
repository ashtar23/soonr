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

@MainActor
@Observable
final class SessionStore {
    private(set) var state: SessionState = .restoring
    private(set) var signInFailure: FailureReason?
    private(set) var isSigningIn = false
    private(set) var isSigningOut = false

    @ObservationIgnored private let authentication: any Authenticating
    @ObservationIgnored private let signOutTimeout: Duration

    init(authentication: any Authenticating, signOutTimeout: Duration = .seconds(2)) {
        self.authentication = authentication
        self.signOutTimeout = signOutTimeout
    }

    func restore() async {
        guard case .restoring = state else {
            return
        }

        let session = await authentication.restoreSession()
        AppLog.auth.info("Session restored: \(session != nil, privacy: .public)")
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
            AppLog.auth.error("Sign in failed: \(error)")
            signInFailure = FailureReason(error)
        }
    }

    /// Waits for the server only briefly: the result is discarded either way,
    /// so a slow one must not hold the user on a screen they asked to leave.
    /// The request carries on if it loses the race.
    func signOut() async {
        isSigningOut = true
        defer { isSigningOut = false }

        let serverSignOut = Task { [authentication] in
            try? await authentication.signOut()
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = await serverSignOut.value }
            group.addTask { [signOutTimeout] in try? await Task.sleep(for: signOutTimeout) }
            await group.next()
            group.cancelAll()
        }

        AppLog.auth.info("Signed out")
        state = .signedOut
        signInFailure = nil
    }

    func clearSignInFailure() {
        signInFailure = nil
    }
}
