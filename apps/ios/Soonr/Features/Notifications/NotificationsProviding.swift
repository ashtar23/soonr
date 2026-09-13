protocol NotificationsProviding: Sendable {
    /// The first page, newest first. Paging is deferred with the watchlist's.
    func notifications() async throws -> [NotificationRecord]
    func unreadNotificationCount() async throws -> Int
    /// Returns the notification as the server now holds it.
    func markNotificationRead(id: String) async throws -> NotificationRecord
    /// Returns how many were still unread.
    func markAllNotificationsRead() async throws -> Int
    func notificationPreferences() async throws -> NotificationPreferences
    func updateNotificationPreferences(
        _ preferences: NotificationPreferences
    ) async throws -> NotificationPreferences
}
