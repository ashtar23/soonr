import SwiftUI

/// Preferences are reached from the settings list and from the notifications
/// tab, and neither the account screen nor the settings list between them has
/// any other use for this capability, so it travels in the environment rather
/// than through each of them.
private struct NotificationsProvidingKey: EnvironmentKey {
    static let defaultValue: any NotificationsProviding = UnconfiguredNotifications()
}

extension EnvironmentValues {
    var notifications: any NotificationsProviding {
        get { self[NotificationsProvidingKey.self] }
        set { self[NotificationsProvidingKey.self] = newValue }
    }
}

/// A build with no backend configured has nothing to show and nothing to save.
private struct UnconfiguredNotifications: NotificationsProviding {
    func notifications() async throws -> [NotificationRecord] {
        []
    }

    func unreadNotificationCount() async throws -> Int {
        0
    }

    func markNotificationRead(id: String) async throws -> NotificationRecord {
        throw UnconfiguredNotificationsError.noBackend
    }

    func markAllNotificationsRead() async throws -> Int {
        0
    }

    func notificationPreferences() async throws -> NotificationPreferences {
        .default
    }

    func updateNotificationPreferences(
        _ preferences: NotificationPreferences
    ) async throws -> NotificationPreferences {
        preferences
    }
}

private enum UnconfiguredNotificationsError: Error {
    case noBackend
}
