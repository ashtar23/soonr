import Foundation

struct TitleDetails: Equatable, Sendable {
    let summary: TitleSummary
    let description: String?
    let genres: [String]
    let developers: [String]
    let publishers: [String]
    let releases: [TitleRelease]

    var displayDescription: String? {
        guard let description = description?.trimmingCharacters(in: .whitespacesAndNewlines),
              description.isEmpty == false
        else {
            return nil
        }

        return description
    }
}

extension TitleDetails: Decodable {
    private enum CodingKeys: String, CodingKey {
        case description
        case genres
        case developers
        case publishers
        case releases
    }

    /// The API returns summary and detail fields in one flat object.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            summary: try TitleSummary(from: decoder),
            description: try container.decodeIfPresent(String.self, forKey: .description),
            genres: try container.decode([String].self, forKey: .genres),
            developers: try container.decode([String].self, forKey: .developers),
            publishers: try container.decode([String].self, forKey: .publishers),
            releases: try container.decode([TitleRelease].self, forKey: .releases)
        )
    }
}

struct TitleRelease: Decodable, Equatable, Sendable {
    enum Precision: String, Equatable, Sendable {
        case day
        case month
        case year
        case unknown
    }

    let platformID: String
    let platformName: String
    let releaseDate: String?
    let precision: Precision

    private enum CodingKeys: String, CodingKey {
        case platformID = "platformId"
        case platformName
        case releaseDate
        case precision = "releaseDatePrecision"
    }
}

extension TitleRelease.Precision: Decodable {
    /// Unrecognized precision values degrade to `.unknown` instead of failing
    /// the whole details payload.
    init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: rawValue) ?? .unknown
    }
}

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

        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
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
