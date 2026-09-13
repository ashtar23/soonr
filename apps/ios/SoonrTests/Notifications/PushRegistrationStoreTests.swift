import Foundation
import Testing

@testable import Soonr

@MainActor
@Suite(.tags(.networking))
struct PushRegistrationStoreTests {
    private let token = String(repeating: "a", count: 64)

    @Test
    func permissionGrantedOnAnEarlierLaunchAsksAPNsAgain() async {
        let system = StubPushSystem(authorization: .authorized)
        let store = PushRegistrationStore(
            notifications: StubDeviceRegistrar(),
            system: system
        )

        await store.restore()

        #expect(store.authorization == .authorized)
        #expect(await system.registrations == 1)
    }

    @Test
    func permissionNeverAskedForDoesNotAskAPNs() async {
        let system = StubPushSystem(authorization: .undetermined)
        let store = PushRegistrationStore(
            notifications: StubDeviceRegistrar(),
            system: system
        )

        await store.restore()

        #expect(await system.registrations == 0)
    }

    /// iOS shows the prompt once ever, so a refusal is final until Settings.
    @Test
    func aRefusalIsRememberedAndNotAskedAgain() async {
        let system = StubPushSystem(authorization: .undetermined, grants: false)
        let store = PushRegistrationStore(
            notifications: StubDeviceRegistrar(),
            system: system
        )

        #expect(await store.requestAuthorization() == false)
        #expect(store.authorization == .denied)

        #expect(await store.requestAuthorization() == false)
        #expect(await system.prompts == 1)
    }

    @Test
    func aTokenWithoutASessionIsNotSentAnywhere() async {
        let registrar = StubDeviceRegistrar()
        let store = PushRegistrationStore(
            notifications: registrar,
            system: StubPushSystem(authorization: .authorized)
        )
        await store.restore()

        await store.tokenReceived(token)

        #expect(await registrar.registered.isEmpty)
        #expect(store.isRegistered == false)
    }

    /// The token and the session arrive in whichever order the launch produces.
    @Test
    func aTokenArrivingBeforeTheSessionIsSentOnceItExists() async {
        let registrar = StubDeviceRegistrar()
        let store = PushRegistrationStore(
            notifications: registrar,
            system: StubPushSystem(authorization: .authorized)
        )
        await store.restore()

        await store.tokenReceived(token)
        await store.signedIn()

        #expect(await registrar.registered.map(\.token) == [token])
        #expect(store.isRegistered)
    }

    @Test
    func aTokenArrivingAfterTheSessionIsSentStraightAway() async {
        let registrar = StubDeviceRegistrar()
        let store = PushRegistrationStore(
            notifications: registrar,
            system: StubPushSystem(authorization: .authorized)
        )
        await store.restore()

        await store.signedIn()
        await store.tokenReceived(token)

        #expect(await registrar.registered.map(\.token) == [token])
    }

    @Test
    func withoutPermissionNothingIsSentEvenWhenSignedIn() async {
        let registrar = StubDeviceRegistrar()
        let store = PushRegistrationStore(
            notifications: registrar,
            system: StubPushSystem(authorization: .denied)
        )
        await store.restore()

        await store.signedIn()
        await store.tokenReceived(token)

        #expect(await registrar.registered.isEmpty)
    }

    @Test
    func theEnvironmentTravelsWithTheToken() async {
        let registrar = StubDeviceRegistrar()
        let store = PushRegistrationStore(
            notifications: registrar,
            system: StubPushSystem(authorization: .authorized),
            environment: .production
        )
        await store.restore()

        await store.signedIn()
        await store.tokenReceived(token)

        #expect(await registrar.registered.map(\.environment) == [.production])
    }

    /// Otherwise the next account signing in on this device would receive the
    /// previous one's notifications.
    @Test
    func signingOutTakesTheDeviceBack() async {
        let registrar = StubDeviceRegistrar()
        let store = PushRegistrationStore(
            notifications: registrar,
            system: StubPushSystem(authorization: .authorized)
        )
        await store.restore()
        await store.signedIn()
        await store.tokenReceived(token)

        await store.signedOut()

        #expect(await registrar.unregistered == [token])
        #expect(store.isRegistered == false)
    }

    @Test
    func signingOutWithNothingRegisteredSendsNothing() async {
        let registrar = StubDeviceRegistrar()
        let store = PushRegistrationStore(
            notifications: registrar,
            system: StubPushSystem(authorization: .authorized)
        )

        await store.signedOut()

        #expect(await registrar.unregistered.isEmpty)
    }

    /// APNs re-delivers the same token on most launches.
    @Test
    func theSameTokenIsNotUploadedTwice() async {
        let registrar = StubDeviceRegistrar()
        let store = PushRegistrationStore(
            notifications: registrar,
            system: StubPushSystem(authorization: .authorized)
        )
        await store.restore()
        await store.signedIn()

        await store.tokenReceived(token)
        await store.tokenReceived(token)

        #expect(await registrar.registered.count == 1)
    }

    @Test
    func aRotatedTokenReplacesTheOneTheServerHolds() async {
        let registrar = StubDeviceRegistrar()
        let store = PushRegistrationStore(
            notifications: registrar,
            system: StubPushSystem(authorization: .authorized)
        )
        await store.restore()
        await store.signedIn()

        await store.tokenReceived(token)
        await store.tokenReceived(String(repeating: "b", count: 64))

        #expect(await registrar.registered.count == 2)
    }

    /// A push puts a number on the icon and iOS leaves it there; reading the
    /// notifications is what has to take it down.
    @Test
    func theBadgeFollowsWhatIsStillUnread() async {
        let system = StubPushSystem(authorization: .authorized)
        let store = PushRegistrationStore(
            notifications: StubDeviceRegistrar(),
            system: system
        )

        await store.showBadge(3)
        await store.showBadge(0)

        #expect(await system.badgeCounts == [3, 0])
    }

    @Test
    func aRejectedUploadLeavesTheDeviceUnregistered() async {
        let registrar = StubDeviceRegistrar(failing: true)
        let store = PushRegistrationStore(
            notifications: registrar,
            system: StubPushSystem(authorization: .authorized)
        )
        await store.restore()
        await store.signedIn()

        await store.tokenReceived(token)

        #expect(store.isRegistered == false)
    }
}

private actor StubPushSystem: PushAuthorizing {
    private(set) var registrations = 0
    private(set) var prompts = 0
    private(set) var badgeCounts: [Int] = []

    private let status: PushAuthorization
    private let grants: Bool

    init(authorization: PushAuthorization, grants: Bool = true) {
        status = authorization
        self.grants = grants
    }

    func authorization() async -> PushAuthorization {
        status
    }

    func requestAuthorization() async -> Bool {
        prompts += 1
        return grants
    }

    func registerForRemoteNotifications() async {
        registrations += 1
    }

    func setBadgeCount(_ count: Int) async {
        badgeCounts.append(count)
    }
}

private actor StubDeviceRegistrar: NotificationsProviding {
    private(set) var registered: [(token: String, environment: PushEnvironment)] = []
    private(set) var unregistered: [String] = []

    private let failing: Bool

    init(failing: Bool = false) {
        self.failing = failing
    }

    func registerDevice(token: String, environment: PushEnvironment) async throws {
        if failing {
            throw URLError(.notConnectedToInternet)
        }

        registered.append((token, environment))
    }

    func unregisterDevice(token: String) async throws {
        unregistered.append(token)
    }

    func notifications() async throws -> [NotificationRecord] { [] }

    func unreadNotificationCount() async throws -> Int { 0 }

    func markNotificationRead(id: String) async throws -> NotificationRecord {
        .previewUnread
    }

    func markAllNotificationsRead() async throws -> Int { 0 }

    func notificationPreferences() async throws -> NotificationPreferences { .default }

    func updateNotificationPreferences(
        _ preferences: NotificationPreferences
    ) async throws -> NotificationPreferences {
        preferences
    }
}
