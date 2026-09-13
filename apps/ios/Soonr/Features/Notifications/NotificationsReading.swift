/// What the list and its unread count need. Split from the other two
/// notification capabilities so a stub only implements what it is asked for.
protocol NotificationsReading: Sendable {
    /// Newest first. `cursor` is `nil` for the first page and otherwise the
    /// `nextCursor` of the page before it.
    func notifications(after cursor: String?) async throws -> Page<NotificationRecord>
    func unreadNotificationCount() async throws -> Int
    /// Returns the notification as the server now holds it.
    func markNotificationRead(id: String) async throws -> NotificationRecord
    /// Returns how many were still unread.
    func markAllNotificationsRead() async throws -> Int
}
