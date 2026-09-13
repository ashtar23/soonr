import Foundation
import SwiftUI
import Testing

@testable import Soonr

/// Layout references for the notifications list. The unread dot keeps its
/// column when it is invisible, which is exactly the kind of alignment nothing
/// we assert about the store can see.
@MainActor
@Suite(.enabled(if: ViewSnapshot.isSupported))
struct NotificationRowSnapshotTests {
    @Test
    func rowsAtTheDefaultTextSize() throws {
        try ViewSnapshot.expect(
            rows,
            named: "NotificationRow-Default",
            size: CGSize(width: 390, height: 180)
        )
    }

    /// Artwork gives way to text at accessibility sizes.
    @Test
    func rowsAtAnAccessibilityTextSize() throws {
        try ViewSnapshot.expect(
            rows,
            named: "NotificationRow-Accessibility",
            size: CGSize(width: 390, height: 520),
            dynamicTypeSize: .accessibility3
        )
    }

    @Test
    func rowsInDarkMode() throws {
        try ViewSnapshot.expect(
            rows,
            named: "NotificationRow-Dark",
            size: CGSize(width: 390, height: 180),
            colorScheme: .dark
        )
    }

    /// An unread notification above a read one. The list paints the unread
    /// fill through `listRowBackground`, which needs a `List` and so cannot be
    /// rendered here; this draws the same view behind the row instead.
    private var rows: some View {
        VStack(spacing: 0) {
            NotificationRow(record: .snapshotUnread, now: .snapshotNow)
                .padding(.horizontal, 16)
                .background(UnreadRowBackground())

            NotificationRow(record: .snapshotRead, now: .snapshotNow)
                .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
    }
}

private extension Date {
    static let snapshotNow = Date(timeIntervalSince1970: 1_767_268_800)  // 2026-01-01T12:00Z
}

private extension NotificationRecord {
    /// Two hours before `Date.snapshotNow`.
    static let snapshotUnread = NotificationRecord(
        id: "snapshot-unread",
        eventType: .releaseApproaching,
        destinationTitleID: "rawg:upcoming",
        titleName: "Marvel's Wolverine",
        titleArtworkURL: nil,
        message: "Release approaching",
        subtitle: "Releases in 7 days on September 15, 2026",
        createdAt: "2026-01-01T10:00:00.000Z",
        readAt: nil
    )

    /// Old enough to be captioned with a date rather than an age.
    static let snapshotRead = NotificationRecord(
        id: "snapshot-read",
        eventType: .releaseDateChanged,
        destinationTitleID: "rawg:3498",
        titleName: "Grand Theft Auto VI",
        titleArtworkURL: nil,
        message: "Release date changed",
        subtitle: nil,
        createdAt: "2025-12-20T12:00:00.000Z",
        readAt: "2025-12-20T14:00:00.000Z"
    )
}
