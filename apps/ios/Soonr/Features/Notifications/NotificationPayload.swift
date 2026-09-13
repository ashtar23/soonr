import Foundation

/// What a notification was about, as data rather than as the sentence the
/// server wrote when it generated the row.
enum NotificationPayload: Hashable, Sendable {
    case releaseApproaching(targetReleaseDate: String?)
    case releaseDateChanged(nextReleaseDate: String?)
    /// An event this build does not know how to describe, which falls back to
    /// the server's own words.
    case unrecognized
}

extension NotificationPayload: Decodable {
    private enum CodingKeys: String, CodingKey {
        case targetReleaseDate
        case nextReleaseDate
    }

    /// The two payloads are told apart by their keys rather than by the record's
    /// event type, so an event type this build has never heard of still gets a
    /// date out of a payload shaped like one it knows.
    init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = .unrecognized
            return
        }

        if container.contains(.targetReleaseDate) {
            self = .releaseApproaching(
                targetReleaseDate: try? container.decode(String?.self, forKey: .targetReleaseDate)
            )
        } else if container.contains(.nextReleaseDate) {
            self = .releaseDateChanged(
                nextReleaseDate: try? container.decode(String?.self, forKey: .nextReleaseDate)
            )
        } else {
            self = .unrecognized
        }
    }
}

/// How a notification reads today, rather than on the day it was generated.
///
/// The server writes the sentence once and stores it: a row generated on
/// release day still says "Releases today" a week later. Everything needed to
/// say it correctly is in the payload, so the row says it itself and the
/// server's copy is the fallback.
enum NotificationCaption {
    static func text(
        for record: NotificationRecord,
        now: Date = .now,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        derived(for: record, now: now, locale: locale)
            ?? record.subtitle
            ?? record.message
    }

    private static func derived(
        for record: NotificationRecord,
        now: Date,
        locale: Locale
    ) -> String? {
        switch record.payload {
        case let .releaseApproaching(date):
            return releaseText(date, now: now, locale: locale)
        case let .releaseDateChanged(date):
            guard let text = date.map({ formatted($0, locale: locale) }) ?? nil else {
                return nil
            }

            return "Moved to \(text)"
        case .unrecognized:
            return nil
        }
    }

    private static func releaseText(_ date: String?, now: Date, locale: Locale) -> String? {
        guard let date, let formattedDate = formatted(date, locale: locale) else {
            return nil
        }

        guard let days = ReleaseDateText.daysUntil(date, now: now) else {
            return formattedDate
        }

        return switch days {
        case ..<0: "Out now"
        case 0: "Out today"
        case 1: "Out tomorrow"
        // Past a month a count of days stops meaning anything, and the date
        // says it better.
        case 2...30: "In \(days) days"
        default: formattedDate
        }
    }

    private static func formatted(_ isoDate: String, locale: Locale) -> String? {
        let text = ReleaseDateText.format(isoDate, precision: .day, locale: locale)
        return text == ReleaseDateText.unannounced ? nil : text
    }
}
