import Foundation

/// Unlike a release date, this is an instant rather than a calendar day, so it
/// is parsed as a full timestamp and shown in the viewer's own time zone.
enum NotificationTimestamp {
    /// An age up to a week ("2 hours ago"), a date after that, where the age
    /// stops being easier to picture than the day.
    static func text(
        _ timestamp: String,
        now: Date = .now,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        guard let date = date(from: timestamp) else {
            return nil
        }

        let age = now.timeIntervalSince(date)
        if age < 60 {
            return "Just now"
        }

        if age < sevenDays {
            // `.relative` can only measure from the present moment, and a list
            // that is being read wants the age at the time it was drawn.
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = locale
            formatter.dateTimeStyle = .named
            return formatter.localizedString(for: date, relativeTo: now)
        }

        return date.formatted(
            Date.FormatStyle(locale: locale).year().month(.abbreviated).day()
        )
    }

    private static let sevenDays: TimeInterval = 7 * 24 * 60 * 60

    /// The API sends fractional seconds; accepting one without them costs a
    /// line and outlives a change to how it is serialized.
    private static func date(from timestamp: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            .parse(timestamp)
        {
            return date
        }

        return try? Date.ISO8601FormatStyle().parse(timestamp)
    }
}
