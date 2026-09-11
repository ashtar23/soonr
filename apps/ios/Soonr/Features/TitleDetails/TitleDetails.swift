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
