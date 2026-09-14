import Foundation

/// Which stretch of time a notification belongs to.
///
/// The list is a record of what happened rather than a catalogue of things
/// chosen, and headings are what say so: the rows stay the rows every other
/// list uses, and the screen still reads as a timeline.
enum NotificationTimeGroup: Hashable, CaseIterable, Sendable {
    case today
    case thisWeek
    case earlier

    var title: String {
        switch self {
        case .today: "Today"
        case .thisWeek: "This week"
        case .earlier: "Earlier"
        }
    }
}

/// A heading and the notifications under it.
struct NotificationSection: Identifiable, Equatable, Sendable {
    let group: NotificationTimeGroup
    let records: [NotificationRecord]

    var id: NotificationTimeGroup { group }
}

extension NotificationTimeGroup {
    /// Calendar days rather than elapsed hours: something from late last night
    /// belongs under yesterday even though it is only a few hours old, which is
    /// how a reader thinks about it.
    static func of(
        _ timestamp: String,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> NotificationTimeGroup {
        guard let date = NotificationTimestamp.date(from: timestamp) else {
            // Undatable rather than old: it sorts where the server put it, and
            // the last group is the one that makes no claim about when.
            return .earlier
        }

        if calendar.isDate(date, inSameDayAs: now) {
            return .today
        }

        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) else {
            return .earlier
        }

        return date > weekAgo ? .thisWeek : .earlier
    }

    /// Groups without reordering: the server sends newest first, and that order
    /// is what puts each group's rows in the right sequence and the groups
    /// themselves in the right order.
    static func sections(
        for records: [NotificationRecord],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [NotificationSection] {
        var sections: [NotificationSection] = []

        for record in records {
            let group = of(record.createdAt, now: now, calendar: calendar)

            if let last = sections.last, last.group == group {
                sections[sections.count - 1] = NotificationSection(
                    group: group,
                    records: last.records + [record]
                )
            } else {
                sections.append(NotificationSection(group: group, records: [record]))
            }
        }

        return sections
    }
}
