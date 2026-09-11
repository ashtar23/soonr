import Foundation

/// In-memory title data for SwiftUI previews. Performs no network requests.
struct PreviewTitleCatalog: TitleSearching, TitleDetailsLoading {
    var results: [TitleSummary] = [.previewUpcoming, .preview]
    var details: TitleDetails? = .preview

    func searchTitles(query: String) async throws -> [TitleSummary] {
        results
    }

    func titleDetails(id: String) async throws -> TitleDetails? {
        details
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

    /// Releases four days from whenever the preview renders.
    static let previewUpcoming = TitleSummary(
        id: "rawg:upcoming",
        kind: "game",
        source: "rawg",
        externalID: "0",
        slug: "upcoming-game",
        name: "Marvel's Wolverine",
        coverImageURL: nil,
        earliestReleaseDate: Date.now
            .addingTimeInterval(4 * 24 * 60 * 60)
            .formatted(.iso8601.year().month().day()),
        platforms: [TitlePlatform(id: "rawg-platform:187", name: "PlayStation 5")],
        rawgRating: nil,
        rawgRatingsCount: nil,
        rawgMetacritic: nil,
        rawgAdded: nil,
        rawgReviewsCount: nil,
        rawgSuggestionsCount: nil,
        rawgRatingTop: nil
    )
}

extension TitleDetails {
    static let preview = TitleDetails(
        summary: .preview,
        description: "Rockstar Games went bigger with an open world spanning Los Santos and Blaine County.",
        genres: ["Action", "Adventure"],
        developers: ["Rockstar North", "Rockstar Games"],
        publishers: ["Rockstar Games"],
        releases: [
            TitleRelease(
                platformID: "rawg-platform:4",
                platformName: "PC",
                releaseDate: "2015-04-14",
                precision: .day
            ),
            TitleRelease(
                platformID: "rawg-platform:18",
                platformName: "PlayStation 4",
                releaseDate: "2014-11-18",
                precision: .day
            ),
            TitleRelease(
                platformID: "rawg-platform:187",
                platformName: "PlayStation 5",
                releaseDate: nil,
                precision: .unknown
            ),
        ]
    )

    static let previewSparse = TitleDetails(
        summary: .preview,
        description: nil,
        genres: [],
        developers: [],
        publishers: [],
        releases: []
    )
}
