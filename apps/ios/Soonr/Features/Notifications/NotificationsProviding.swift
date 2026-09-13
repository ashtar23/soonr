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
    /// Registering the same device again is how a rotated token replaces the
    /// one the server holds.
    func registerDevice(token: String, environment: PushEnvironment) async throws
    func unregisterDevice(token: String) async throws
}

/// A token minted by a development build is only deliverable through the APNs
/// sandbox, and one from TestFlight or the App Store only through production.
/// The server keeps this per device and picks its host from it.
enum PushEnvironment: String, Codable, Sendable {
    case sandbox
    case production

    /// `aps-environment` is `development` in a debug build and `production`
    /// in any distributed one, and `DEBUG` tracks the same split.
    static var current: PushEnvironment {
        #if DEBUG
            .sandbox
        #else
            .production
        #endif
    }
}
