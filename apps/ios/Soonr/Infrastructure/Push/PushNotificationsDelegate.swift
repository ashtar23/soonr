import UIKit
import UserNotifications

/// APNs hands the device token to the app delegate, which UIKit creates
/// itself, so the token reaches the app through a stream the root consumes —
/// the same shape `AppDependencies` uses for rejected sessions.
enum PushDeviceTokens {
    private static let channel = AsyncStream<String>.makeStream()

    static var tokens: AsyncStream<String> {
        channel.stream
    }

    static func received(_ token: Data) {
        channel.continuation.yield(token.map { String(format: "%02x", $0) }.joined())
    }
}

/// A notification the viewer tapped, and what it was about.
struct OpenedPushNotification: Hashable, Sendable {
    let notificationID: String
    let destination: TitleDestination
}

enum OpenedPushNotifications {
    private static let channel = AsyncStream<OpenedPushNotification>.makeStream()

    static var opened: AsyncStream<OpenedPushNotification> {
        channel.stream
    }

    static func received(_ response: UNNotificationResponse) {
        let content = response.notification.request.content
        guard let opened = parse(userInfo: content.userInfo, title: content.title) else {
            return
        }

        channel.continuation.yield(opened)
    }

    /// The keys `apps/api` puts alongside the alert. The alert's own title is
    /// the game's name, which is what the details screen shows until its own
    /// request answers.
    static func parse(
        userInfo: [AnyHashable: Any],
        title: String
    ) -> OpenedPushNotification? {
        guard let titleID = userInfo["destinationTitleId"] as? String,
            let notificationID = userInfo["notificationId"] as? String,
            titleID.isEmpty == false
        else {
            return nil
        }

        return OpenedPushNotification(
            notificationID: notificationID,
            destination: TitleDestination(id: titleID, name: title)
        )
    }
}

final class PushNotificationsDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushDeviceTokens.received(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        // Common and not fatal: no network, or a build whose entitlement does
        // not match the provisioning profile. Nothing is sent until a token
        // arrives, so the app carries on without one.
        AppLog.notifications.error("Could not register for push: \(error)")
    }
}

// `@preconcurrency`, not `nonisolated`: UIKit finishes this delegate's work
// inside a CATransaction commit and asserts if that happens off the main
// thread. Marking the methods nonisolated to satisfy Swift 6's Sendable
// checking moved them to a background executor, and tapping a notification
// crashed the app.
extension PushNotificationsDelegate: @preconcurrency UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        OpenedPushNotifications.received(response)
    }

    /// Shown even with Soonr open. The list behind it is not necessarily on
    /// screen, so suppressing it would drop the only sign that anything
    /// arrived.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}

/// The live system side. Everything here is either UIKit or
/// `UNUserNotificationCenter`, which is why it sits behind `PushAuthorizing`.
struct SystemPushAuthorization: PushAuthorizing {
    func authorization() async -> PushAuthorization {
        switch await UNUserNotificationCenter.current().notificationSettings()
            .authorizationStatus
        {
        case .notDetermined:
            return .undetermined
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return .authorized
        @unknown default:
            return .undetermined
        }
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            AppLog.notifications.error("Could not ask for push permission: \(error)")
            return false
        }
    }

    @MainActor
    func registerForRemoteNotifications() async {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func setBadgeCount(_ count: Int) async {
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(count)
        } catch {
            AppLog.notifications.error("Could not set the badge: \(error)")
        }
    }
}
