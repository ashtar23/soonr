/// What the server pushes down the notifications socket.
///
/// The server sends no notification records: a change is an invalidation, and
/// what arrives is only the news that something moved. Refetching is what makes
/// the list correct, which also means a missed event costs nothing beyond
/// latency — the next refresh settles it either way.
enum NotificationStreamEvent: Equatable, Sendable {
    /// The list or the unread count changed.
    case recordsChanged
    /// Preferences changed, carrying the new copy when the server knows it.
    /// It arrives without one when the payload cannot be trusted, which asks
    /// the reader to refetch instead.
    case preferencesChanged(NotificationPreferences?)
}

/// A stream that outlives any single connection: it reconnects on its own, so
/// a consumer iterates once and stops by ending the iteration.
protocol NotificationStreaming: Sendable {
    func notificationEvents() -> AsyncStream<NotificationStreamEvent>
}
