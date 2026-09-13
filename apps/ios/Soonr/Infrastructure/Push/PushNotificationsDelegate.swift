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

final class PushNotificationsDelegate: NSObject, UIApplicationDelegate {
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
}
