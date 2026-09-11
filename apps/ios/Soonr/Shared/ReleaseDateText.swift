import Foundation

/// Presentation helpers for API release dates (`YYYY`, `YYYY-MM`, or
/// `YYYY-MM-DD`). Release dates are calendar days, so they are interpreted in
/// UTC to avoid shifting across time zones.
enum ReleaseDateText {
    static let unannounced = "TBA"

    static func format(
        _ isoDate: String?,
        precision: TitleRelease.Precision,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        guard precision != .unknown,
            let isoDate,
            let date = date(fromISODate: isoDate)
        else {
            return unannounced
        }

        let style = Date.FormatStyle(
            locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        switch precision {
        case .day:
            return date.formatted(style.year().month(.abbreviated).day())
        case .month:
            return date.formatted(style.year().month(.wide))
        case .year:
            return date.formatted(style.year())
        case .unknown:
            return unannounced
        }
    }

    /// Calendar days from the viewer's current local date until the release
    /// date. Negative for past releases; `nil` when the date is missing or
    /// malformed.
    static func daysUntil(
        _ isoDate: String?,
        now: Date = .now,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> Int? {
        guard let isoDate, let releaseDate = date(fromISODate: isoDate) else {
            return nil
        }

        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = timeZone
        let today = localCalendar.dateComponents([.year, .month, .day], from: now)
        guard let todayDate = calendar.date(from: today) else {
            return nil
        }

        return calendar.dateComponents([.day], from: todayDate, to: releaseDate).day
    }

    /// A short badge for releases that are today or still ahead.
    static func countdown(daysUntil days: Int) -> String? {
        switch days {
        case ..<0:
            nil
        case 0:
            "Out today"
        case 1:
            "Tomorrow"
        case 2...30:
            "In \(days) days"
        default:
            "Upcoming"
        }
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private static func date(fromISODate value: String) -> Date? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { part in
            part.allSatisfy { $0.isASCII && $0.isNumber } ? Int(part) : nil
        }
        guard (1...3).contains(parts.count),
            numbers.count == parts.count,
            parts[0].count == 4
        else {
            return nil
        }

        let components = DateComponents(
            year: numbers[0],
            month: numbers.count > 1 ? numbers[1] : 1,
            day: numbers.count > 2 ? numbers[2] : 1
        )
        guard components.isValidDate(in: calendar) else {
            return nil
        }

        return calendar.date(from: components)
    }
}
