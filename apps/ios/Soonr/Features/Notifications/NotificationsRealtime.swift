import Foundation

/// Fans one connection out to the two stores that care about it.
///
/// Both the list and the preferences screen react to the same socket, and a
/// stream has one consumer, so the split happens here rather than by opening a
/// second connection the server would have to hold open as well.
///
/// When to run is not decided here — see the app root, which starts this on the
/// way in and stops it on the way out.
@MainActor
final class NotificationsRealtime {
    private let stream: any NotificationStreaming
    private let records: NotificationsStore
    private let preferences: NotificationPreferencesStore
    private var task: Task<Void, Never>?

    var isRunning: Bool {
        task != nil
    }

    init(
        stream: any NotificationStreaming,
        records: NotificationsStore,
        preferences: NotificationPreferencesStore
    ) {
        self.stream = stream
        self.records = records
        self.preferences = preferences
    }

    /// Starting twice is the same as starting once: the scene becoming active
    /// is one of the callers, and it happens more than once per launch.
    func start() {
        guard task == nil else {
            return
        }

        task = Task { [stream, records, preferences] in
            for await event in stream.notificationEvents() {
                switch event {
                case .recordsChanged:
                    // The event carries no records, so the store decides what
                    // answering it costs: nothing for a change of its own, and
                    // one refetch for a burst of anyone else's.
                    await records.changedRemotely()
                case let .preferencesChanged(pushed):
                    await preferences.apply(pushed)
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
