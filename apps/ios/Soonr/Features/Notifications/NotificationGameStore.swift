import Foundation
import Observation

/// What one game has said, asked about directly.
///
/// The list can only group what it has paged in, so a collapsed row counts the
/// notifications in hand rather than the ones that exist — it says "+2" and
/// means "+5" until three more pages have loaded. The sheet asks the server
/// instead, which is the only way for it to be right.
///
/// It opens on what the list already held so there is something to read at
/// once, and replaces it with the server's answer. A game heard from twice
/// looks the same either way; a game whose older notifications were never
/// paged in fills in.
@MainActor
@Observable
final class NotificationGameStore {
    private(set) var records: [NotificationRecord]
    /// Set when the server could not be reached. The rows already shown are
    /// still worth reading, so this is reported beside them rather than
    /// instead of them.
    private(set) var loadFailed = false

    @ObservationIgnored private let titleID: String
    /// The list this game's notifications are part of. It owns the service and
    /// the read state, so asking it keeps one copy of both.
    @ObservationIgnored private let list: NotificationsStore

    init(
        titleID: String,
        showing records: [NotificationRecord],
        in list: NotificationsStore
    ) {
        self.titleID = titleID
        self.records = records
        self.list = list
    }

    func load() async {
        do {
            let loaded = try await list.records(about: titleID)
            try Task.checkCancellation()
            // An empty answer means every one of them was read and removed
            // elsewhere, which is worth showing; it is not a failure.
            records = loaded
            loadFailed = false
        } catch is CancellationError {
            return
        } catch {
            AppLog.notifications.error("Could not load a game's notifications: \(error)")
            loadFailed = true
        }
    }

    /// Marks one read here and in the list behind, so the row, the collapsed
    /// row it sits under, and the badge all move together.
    func markRead(id: String) async {
        guard let index = records.firstIndex(where: { $0.id == id }),
            records[index].isRead == false
        else {
            return
        }

        let previous = records
        records[index] = NotificationRecord(
            records[index],
            readAt: ISO8601DateFormatter().string(from: .now)
        )

        await list.markRead(id: id)

        // The list holds what the server confirmed, so it is the better copy
        // wherever it has one.
        if let confirmed = list.state.records?.first(where: { $0.id == id }) {
            records[index] = confirmed
        } else if list.state.records?.isEmpty == false {
            records = previous
        }
    }
}
