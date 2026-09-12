import Foundation
import SwiftUI
import Testing

@testable import Soonr

/// Layout references for the row and card shared by search, Home, and details.
/// These exist because a row whose artwork overflowed its frame shipped past a
/// green suite: nothing we assert about models can see layout.
@MainActor
@Suite(.enabled(if: ViewSnapshot.isSupported))
struct TitleRowSnapshotTests {
    @Test
    func rowsAtTheDefaultTextSize() throws {
        try ViewSnapshot.expect(
            rows,
            named: "TitleRow-Default",
            size: CGSize(width: 390, height: 180)
        )
    }

    /// The row swaps to a stacked layout at accessibility sizes, which is the
    /// part most likely to break unnoticed.
    @Test
    func rowsAtAnAccessibilityTextSize() throws {
        try ViewSnapshot.expect(
            rows,
            named: "TitleRow-Accessibility",
            // Tall enough to leave empty space below the second row, so a
            // regression that pushes content down is visible rather than
            // cropped away.
            size: CGSize(width: 390, height: 520),
            dynamicTypeSize: .accessibility3
        )
    }

    @Test
    func rowsInDarkMode() throws {
        try ViewSnapshot.expect(
            rows,
            named: "TitleRow-Dark",
            size: CGSize(width: 390, height: 180),
            colorScheme: .dark
        )
    }

    @Test
    func cardsInARail() throws {
        try ViewSnapshot.expect(
            HStack(alignment: .top, spacing: 16) {
                TitleCard(title: .snapshotUpcoming, now: .snapshotNow)
                TitleCard(title: .snapshotReleased, now: .snapshotNow)
            }
            .padding(16),
            named: "TitleCard-Rail",
            size: CGSize(width: 460, height: 230)
        )
    }

    /// An upcoming title, which carries a countdown badge, above a released
    /// one, which does not.
    private var rows: some View {
        VStack(spacing: 0) {
            TitleRow(title: .snapshotUpcoming, now: .snapshotNow)
            TitleRow(title: .snapshotReleased, now: .snapshotNow)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }
}

private extension Date {
    /// Midday UTC, so the viewer's time zone cannot shift the countdown by a
    /// day and change the badge text.
    static let snapshotNow = Date(timeIntervalSince1970: 1_767_268_800)
}

private extension TitleSummary {
    /// Four days after `Date.snapshotNow`, so the badge reads "In 4 days".
    static let snapshotUpcoming = snapshot(
        id: "rawg:upcoming",
        name: "Marvel's Wolverine",
        earliestReleaseDate: "2026-01-05",
        platforms: [TitlePlatform(id: "rawg-platform:187", name: "PlayStation 5")]
    )

    static let snapshotReleased = snapshot(
        id: "rawg:3498",
        name: "Grand Theft Auto V",
        earliestReleaseDate: "2013-09-17",
        platforms: [
            TitlePlatform(id: "rawg-platform:4", name: "PC"),
            TitlePlatform(id: "rawg-platform:18", name: "PlayStation 4"),
            TitlePlatform(id: "rawg-platform:1", name: "Xbox One"),
        ]
    )

    /// Artwork is deliberately absent: `AsyncImage` cannot load during a
    /// render, so a URL would only add a placeholder that may or may not have
    /// resolved.
    private static func snapshot(
        id: String,
        name: String,
        earliestReleaseDate: String,
        platforms: [TitlePlatform]
    ) -> TitleSummary {
        TitleSummary(
            id: id,
            kind: "game",
            source: "rawg",
            externalID: "0",
            slug: "snapshot",
            name: name,
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
