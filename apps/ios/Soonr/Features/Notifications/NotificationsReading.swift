/// What the list and its unread count need. Split from the other two
/// notification capabilities so a stub only implements what it is asked for.
protocol NotificationsReading: Sendable {
    /// The first page, newest first. Paging is deferred with the watchlist's.
    func notifications() async throws -> [NotificationRecord]
    func unreadNotificationCount() async throws -> Int
    /// Returns the notification as the server now holds it.
    func markNotificationRead(id: String) async throws -> NotificationRecord
    /// Returns how many were still unread.
    func markAllNotificationsRead() async throws -> Int
}
