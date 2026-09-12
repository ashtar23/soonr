import Foundation
import Testing

@testable import Soonr

@MainActor
@Suite(.tags(.networking))
struct SessionStoreTests {
    @Test
    func restoringWithoutAStoredSessionSignsOut() async {
        let store = SessionStore(authentication: PreviewAuthentication(restored: nil))

        await store.restore()

        #expect(store.state == .signedOut)
    }

    @Test
    func aStoredSessionIsRestored() async {
        let store = SessionStore(authentication: PreviewAuthentication(restored: .preview))

        await store.restore()

        #expect(store.state == .signedIn(.preview))
    }

    @Test
    func signingInStoresTheSession() async {
        let store = SessionStore(authentication: PreviewAuthentication())

        await store.signIn(email: " player@soonr.app ", password: "hunter2")

        #expect(store.state == .signedIn(.preview))
        #expect(store.signInFailure == nil)
        #expect(store.isSigningIn == false)
    }

    @Test
    func failedSignInKeepsTheUserSignedOutAndExplainsWhy() async {
        let store = SessionStore(
            authentication: PreviewAuthentication(signInResult: .failure(.invalidCredentials))
        )

        await store.signIn(email: "player@soonr.app", password: "wrong")

        #expect(store.state == .restoring)
        #expect(store.signInFailure?.message == "Those credentials didn't work.")
    }

    @Test
    func signingOutClearsTheSessionAndAnyFailure() async {
        let store = SessionStore(authentication: PreviewAuthentication(restored: .preview))
        await store.restore()

        await store.signOut()

        #expect(store.state == .signedOut)
        #expect(store.signInFailure == nil)
    }

    /// The wait is capped. A server that never answers must not hold someone
    /// on a screen they asked to leave.
    @Test
    func signingOutGivesUpOnAServerThatNeverAnswers() async {
        let store = SessionStore(
            authentication: HangingSignOut(restored: .preview),
            signOutTimeout: .milliseconds(10)
        )
        await store.restore()

        await store.signOut()

        #expect(store.state == .signedOut)
        #expect(store.isSigningOut == false)
    }

    @Test
    func restoringOnlyRunsOnce() async {
        let store = SessionStore(authentication: PreviewAuthentication(restored: .preview))

        await store.restore()
        await store.signOut()
        // A second restore, such as the app returning to the foreground, must
        // not resurrect the session the user just left.
        await store.restore()

        #expect(store.state == .signedOut)
    }

    @Test
    func aBuildWithoutSupabaseSettingsExplainsItself() async {
        let store = SessionStore(authentication: UnconfiguredAuthentication())

        await store.restore()
        await store.signIn(email: "player@soonr.app", password: "hunter2")

        #expect(store.state == .signedOut)
        #expect(store.signInFailure?.message.contains("Local.xcconfig") == true)
    }
}

/// Signing out takes far longer than the store is willing to wait, standing in
/// for an unreachable server. Bounded, because the request outlives the wait by
/// design and an unbounded one would hold the whole test run open.
private struct HangingSignOut: Authenticating {
    let restored: UserSession?

    func restoreSession() async -> UserSession? {
        restored
    }

    func accessToken() async -> String? {
        restored?.accessToken
    }

    func signIn(email: String, password: String) async throws -> UserSession {
        throw CancellationError()
    }

    func signOut() async throws {
        try await Task.sleep(for: .milliseconds(500))
    }
}
