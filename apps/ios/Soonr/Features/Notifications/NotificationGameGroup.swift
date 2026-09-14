import Foundation

/// Every loaded notification about one game, newest first.
///
/// A game is told about more than once: four reminders as a release
/// approaches, and the whole sequence again if the date moves. Six rows saying
/// almost the same thing answer "what pinged me" rather than "what is
/// happening to this game", which is the question a list of games should
/// answer.
struct NotificationGameGroup: Identifiable, Equatable, Sendable {
    let titleID: String
    /// Never empty, and in the order the server sent them.
    let records: [NotificationRecord]

    var id: String { titleID }

    /// What the group is worth showing: the newest thing that happened.
    var latest: NotificationRecord {
        // Safe by construction — a group exists because a record made it.
        records[0]
    }

    var isCollapsed: Bool {
        records.count > 1
    }

    /// How many are folded away behind the latest.
    var hiddenCount: Int {
        max(0, records.count - 1)
    }

    var hasUnread: Bool {
        records.contains { $0.isRead == false }
    }
}

extension NotificationGameGroup {
    /// Gathers by game without reordering.
    ///
    /// A group takes the position of its newest notification, which keeps the
    /// list in the order the server sent it and lets the time headings stand:
    /// a game belongs to the stretch of time it was last heard from.
    ///
    /// Counts what is loaded, which is all the list holds. A game's older
    /// notifications can sit on a page not fetched yet, so a group can grow as
    /// the list is paged — see the sheet, which asks about one game directly
    /// rather than inferring it from what happens to be in hand.
    static func groups(for records: [NotificationRecord]) -> [NotificationGameGroup] {
        var order: [String] = []
        var byTitle: [String: [NotificationRecord]] = [:]

        for record in records {
            let titleID = record.destinationTitleID

            if byTitle[titleID] == nil {
                order.append(titleID)
            }

            byTitle[titleID, default: []].append(record)
        }

        return order.compactMap { titleID in
            guard let records = byTitle[titleID], records.isEmpty == false else {
                return nil
            }

            return NotificationGameGroup(titleID: titleID, records: records)
        }
    }
}
