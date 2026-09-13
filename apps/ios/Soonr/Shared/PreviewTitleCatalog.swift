import Foundation

extension TitleDetailsDependencies {
    static var preview: TitleDetailsDependencies { .preview(PreviewTitleCatalog()) }

    static func preview(_ catalog: PreviewTitleCatalog) -> TitleDetailsDependencies {
        TitleDetailsDependencies(titleDetails: catalog)
    }
}

/// Performs no network requests.
struct PreviewTitleCatalog:
    TitleSearching, TitleDetailsLoading, HomeDiscovering, WatchlistManaging, AccountCreating
{
    var results: [TitleSummary] = [.previewUpcoming, .preview]
    var details: TitleDetails? = .preview
    var isInWatchlist = false
    var saved: [WatchlistEntry] = [
        WatchlistEntry(id: "w1", title: .previewUpcoming, addedAt: "2026-01-02T10:00:00Z"),
        WatchlistEntry(id: "w2", title: .preview, addedAt: "2026-01-01T10:00:00Z"),
    ]
    var discovery = HomeDiscovery(
        upcoming: [.previewUpcoming, .preview],
        latest: [.preview],
        popular: [.preview, .previewUpcoming]
    )

    func searchTitles(query: String) async throws -> [TitleSummary] {
        results
    }

    func titleDetails(id: String) async throws -> TitleDetailsResult? {
        details.map { TitleDetailsResult(details: $0, isInWatchlist: isInWatchlist) }
    }

    func homeDiscovery() async throws -> HomeDiscovery {
        discovery
    }

    func watchlist() async throws -> [WatchlistEntry] {
        saved
    }

    /// No-ops: the details model updates the button optimistically, so a
    /// preview still shows the filled and empty states when tapped.
    func addToWatchlist(titleID: String) async throws {}

    func removeFromWatchlist(titleID: String) async throws {}

    func emailAvailability(email: String) async throws -> FieldAvailability {
        FieldAvailability(available: true, reason: nil)
    }

    func usernameAvailability(username: String) async throws -> FieldAvailability {
        FieldAvailability(available: true, reason: nil)
    }

    func signUp(email: String, password: String, username: String) async throws {}
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

extension TitleDestination {
    static let preview = TitleDestination(TitleSummary.preview)
}

extension TitleDetails {
    static let preview = TitleDetails(
        summary: .preview,
        description:
            "Rockstar Games went bigger with an open world spanning Los Santos and Blaine County.",
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
