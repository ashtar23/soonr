import Foundation
import Testing

@testable import Soonr

struct TitleRowTextTests {
    @Test
    func upcomingReleasesShowTheFullDate() {
        let title = TitleSummary.fixture(
            earliestReleaseDate: "2026-09-15",
            platforms: [TitlePlatform(id: "rawg-platform:187", name: "PlayStation 5")]
        )

        let metadata = TitleRowText.metadata(for: title, daysUntilRelease: 3)

        #expect(metadata == "Sep 15, 2026 · PlayStation 5")
    }

    @Test
    func pastReleasesShowTheYear() {
        let title = TitleSummary.fixture(
            earliestReleaseDate: "2013-09-17",
            platforms: [
                TitlePlatform(id: "rawg-platform:4", name: "PC"),
                TitlePlatform(id: "rawg-platform:18", name: "PlayStation 4"),
                TitlePlatform(id: "rawg-platform:1", name: "Xbox One"),
            ]
        )

        let metadata = TitleRowText.metadata(for: title, daysUntilRelease: -1)

        #expect(metadata == "2013 · PC, PlayStation 4 +1")
    }

    @Test
    func titlesWithoutADateAreUnannounced() {
        let title = TitleSummary.fixture(
            earliestReleaseDate: nil,
            platforms: [TitlePlatform(id: "rawg-platform:4", name: "PC")]
        )

        #expect(TitleRowText.metadata(for: title, daysUntilRelease: nil) == "TBA · PC")
    }

    @Test
    func cardsOmitPlatformsSoTheLineDoesNotTruncate() {
        let title = TitleSummary.fixture(
            earliestReleaseDate: "2026-11-19",
            platforms: [
                TitlePlatform(id: "rawg-platform:187", name: "PlayStation 5"),
                TitlePlatform(id: "rawg-platform:4", name: "PC"),
            ]
        )

        let metadata = TitleRowText.metadata(
            for: title,
            daysUntilRelease: 60,
            showsPlatforms: false
        )

        #expect(metadata == "Nov 19, 2026")
    }

    @Test
    func titlesWithoutPlatformsShowOnlyTheRelease() {
        let title = TitleSummary.fixture(earliestReleaseDate: "1994-01-01", platforms: [])

        #expect(TitleRowText.metadata(for: title, daysUntilRelease: -100) == "1994")
    }
}

private extension TitleSummary {
    static func fixture(
        earliestReleaseDate: String?,
        platforms: [TitlePlatform]
    ) -> TitleSummary {
        TitleSummary(
            id: "rawg:1",
            kind: "game",
            source: "rawg",
            externalID: "1",
            slug: "a-game",
            name: "A Game",
            coverImageURL: nil,
            earliestReleaseDate: earliestReleaseDate,
            platforms: platforms,
            rawgRating: nil,
            rawgRatingsCount: nil,
            rawgMetacritic: nil,
            rawgAdded: nil,
            rawgReviewsCount: nil,
            rawgSuggestionsCount: nil,
            rawgRatingTop: nil
        )
    }
}
