import SwiftUI

struct NotificationRow: View {
    let record: NotificationRecord
    var now: Date = .now
    /// How many more this game has said, when the row stands for all of them.
    var hiddenCount = 0

    var body: some View {
        TitleListRow(
            artworkURL: record.titleArtworkURL,
            // The game, not the event: `message` is a category label ("Release
            // approaching") that reads the same on every row.
            title: record.titleName,
            secondary: caption,
            titleWeight: record.isRead ? .regular : .semibold
        ) {
            if hiddenCount > 0 {
                ReleaseBadge(text: "+\(hiddenCount) earlier")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var caption: String? {
        [
            NotificationCaption.text(for: record, now: now),
            NotificationTimestamp.text(record.createdAt, now: now),
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        .nilWhenEmpty
    }

    private var accessibilityLabel: String {
        [
            record.isRead ? nil : "Unread",
            record.titleName,
            caption,
            hiddenCount > 0 ? "\(hiddenCount) earlier" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

private extension String {
    var nilWhenEmpty: String? {
        isEmpty ? nil : self
    }
}
