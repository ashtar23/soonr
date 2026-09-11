import Foundation

struct TitlePlatform: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
}

struct TitleSummary: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: String
    let source: String
    let externalID: String
    let slug: String
    let name: String
    let coverImageURL: URL?
    let earliestReleaseDate: String?
    let platforms: [TitlePlatform]
    let rawgRating: Double?
    let rawgRatingsCount: Double?
    let rawgMetacritic: Double?
    let rawgAdded: Double?
    let rawgReviewsCount: Double?
    let rawgSuggestionsCount: Double?
    let rawgRatingTop: Double?

    var releaseYear: String? {
        guard let earliestReleaseDate else {
            return nil
        }

        let year = earliestReleaseDate.prefix(4)
        guard year.count == 4, year.allSatisfy(\.isNumber) else {
            return nil
        }

        return String(year)
    }

    var platformSummary: String? {
        let names = platforms.prefix(2).map(\.name)
        guard names.isEmpty == false else {
            return nil
        }

        let suffix = platforms.count > names.count ? " +\(platforms.count - names.count)" : ""
        return names.joined(separator: ", ") + suffix
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case source
        case externalID = "externalId"
        case slug
        case name
        case coverImageURL = "coverImageUrl"
        case earliestReleaseDate
        case platforms
        case rawgRating
        case rawgRatingsCount
        case rawgMetacritic
        case rawgAdded
        case rawgReviewsCount
        case rawgSuggestionsCount
        case rawgRatingTop
    }
}
