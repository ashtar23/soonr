/// What the list and its unread count need. Split from the other two
/// notification capabilities so a stub only implements what it is asked for.
protocol NotificationsReading: Sendable {
    /// Newest first. `cursor` is `nil` for the first page and otherwise the
    /// `nextCursor` of the page before it.
    ///
    /// `unreadOnly` narrows the query rather than the page: filtering here
    /// would only ever narrow what had already been loaded, and report nothing
    /// unread while unread notifications sat on a page further down.
    func notifications(
        after cursor: String?,
        unreadOnly: Bool
    ) async throws -> Page<NotificationRecord>
    /// Every notification about one game, newest first.
    ///
    /// Unpaged: four reminders fire for a release and the sequence repeats if
    /// the date moves, so a game's whole history is a handful of rows. Counting
    /// them from the pages the list happens to hold is what made a group say
    /// "+2" and mean "+5".
    func notifications(about titleID: String) async throws -> [NotificationRecord]
    func unreadNotificationCount() async throws -> Int
    /// Returns the notification as the server now holds it.
    func markNotificationRead(id: String) async throws -> NotificationRecord
    /// Returns how many were still unread.
    func markAllNotificationsRead() async throws -> Int
}
