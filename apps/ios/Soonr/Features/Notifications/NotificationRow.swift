import SwiftUI

struct NotificationRow: View {
    let record: NotificationRecord
    var now: Date = .now

    var body: some View {
        TitleListRow(
            artworkURL: record.titleArtworkURL,
            // The game, not the event: `message` is a category label ("Release
            // approaching") that reads the same on every row.
            title: record.titleName,
            secondary: caption,
            titleWeight: record.isRead ? .regular : .semibold
        )
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
        [record.isRead ? nil : "Unread", record.titleName, caption]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

private extension String {
    var nilWhenEmpty: String? {
        isEmpty ? nil : self
    }
}
