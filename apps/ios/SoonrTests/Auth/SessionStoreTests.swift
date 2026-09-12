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
        #expect(store.signInFailure == "Those credentials didn't work.")
    }

    @Test
    func signingOutClearsTheSessionAndAnyFailure() async {
        let store = SessionStore(authentication: PreviewAuthentication(restored: .preview))
        await store.restore()

        await store.signOut()

        #expect(store.state == .signedOut)
        #expect(store.signInFailure == nil)
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
        #expect(store.signInFailure?.contains("Local.xcconfig") == true)
    }
}
