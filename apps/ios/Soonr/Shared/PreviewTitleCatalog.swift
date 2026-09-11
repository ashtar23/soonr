import Foundation

/// In-memory title data for SwiftUI previews. Performs no network requests.
struct PreviewTitleCatalog: TitleSearching {
    var results: [TitleSummary] = [.preview]

    func searchTitles(query: String) async throws -> [TitleSummary] {
        results
    }
}

extension TitleSummary {
    static let preview = TitleSummary(
        id: "rawg:3498",
        kind: "game",
        source: "rawg",
        externalID: "3498",
        slug: "grand-theft-auto-v",
        name: "Grand Theft Auto V",
        coverImageURL: nil,
        earliestReleaseDate: "2013-09-17",
        platforms: [
            TitlePlatform(id: "rawg-platform:4", name: "PC"),
            TitlePlatform(id: "rawg-platform:18", name: "PlayStation 4"),
            TitlePlatform(id: "rawg-platform:1", name: "Xbox One"),
        ],
        rawgRating: 4.47,
        rawgRatingsCount: 7_200,
        rawgMetacritic: 92,
        rawgAdded: 21_000,
        rawgReviewsCount: 690,
        rawgSuggestionsCount: 430,
        rawgRatingTop: 5
    )
}
