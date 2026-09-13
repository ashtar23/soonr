import Foundation
import Observation

/// Keeps the server's idea of this device in step with the system's.
///
/// A token is worth uploading only while someone is signed in, and only while
/// they have granted permission, so the two arrive in either order and the
/// upload happens when both are true.
@MainActor
@Observable
final class PushRegistrationStore {
    private(set) var authorization: PushAuthorization = .undetermined
    /// True once the server holds this device's current token.
    private(set) var isRegistered = false

    @ObservationIgnored private let notifications: any NotificationsProviding
    @ObservationIgnored private let system: any PushAuthorizing
    let environment: PushEnvironment
    /// Shown on the developer screen, which is the only way to see it on a
    /// phone: a device build has no console to read.
    private(set) var deviceToken: String?
    @ObservationIgnored private var isSignedIn = false

    init(
        notifications: any NotificationsProviding,
        system: any PushAuthorizing = SystemPushAuthorization(),
        environment: PushEnvironment = .current
    ) {
        self.notifications = notifications
        self.system = system
        self.environment = environment
    }

    /// Reads what the viewer has already decided, and asks APNs for a token if
    /// they said yes on a previous launch.
    func restore() async {
        authorization = await system.authorization()
        if authorization == .authorized {
            await system.registerForRemoteNotifications()
        }
    }

    /// Shows the system prompt. iOS only ever shows it once, so a viewer who
    /// has already refused is sent to Settings by the screen instead.
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard authorization == .undetermined else {
            return authorization == .authorized
        }

        let granted = await system.requestAuthorization()
        authorization = granted ? .authorized : .denied

        if granted {
            await system.registerForRemoteNotifications()
        }

        return granted
    }

    /// Keeps the icon in step with what the app itself shows. A push sets the
    /// badge and iOS leaves it there, so reading the notifications has to take
    /// it down.
    func showBadge(_ count: Int) async {
        await system.setBadgeCount(count)
    }

    func tokenReceived(_ token: String) async {
        guard token != deviceToken || isRegistered == false else {
            return
        }

        deviceToken = token
        await uploadIfPossible()
    }

    func signedIn() async {
        isSignedIn = true
        await uploadIfPossible()
    }

    /// The device stops being this account's before the session ends, so the
    /// next account's notifications cannot arrive here.
    func signedOut() async {
        isSignedIn = false
        guard let deviceToken, isRegistered else {
            isRegistered = false
            return
        }

        isRegistered = false
        do {
            try await notifications.unregisterDevice(token: deviceToken)
        } catch {
            AppLog.notifications.error("Could not unregister this device: \(error)")
        }
    }

    private func uploadIfPossible() async {
        guard isSignedIn, authorization == .authorized, let deviceToken else {
            return
        }

        do {
            try await notifications.registerDevice(
                token: deviceToken,
                environment: environment
            )
            isRegistered = true
        } catch {
            AppLog.notifications.error("Could not register this device: \(error)")
        }
    }
}
