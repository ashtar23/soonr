protocol NotificationPreferencesProviding: Sendable {
    func notificationPreferences() async throws -> NotificationPreferences
    func updateNotificationPreferences(
        _ preferences: NotificationPreferences
    ) async throws -> NotificationPreferences
}
