import SwiftUI

struct NotificationRow: View {
    let record: NotificationRecord
    var now: Date = .now

    @ScaledMetric(relativeTo: .subheadline) private var artworkWidth: CGFloat = 64
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Artwork is what makes a list of similar sentences scannable, but
            // at accessibility sizes the text needs the whole row.
            if dynamicTypeSize.isAccessibilitySize == false {
                TitleArtwork(url: record.titleArtworkURL, width: .thumbnail, cornerRadius: 8)
                    .frame(width: artworkWidth, height: artworkWidth * 9 / 16)
            }

            VStack(alignment: .leading, spacing: 4) {
                // The game, not the event: `message` is a category label
                // ("Release approaching") that reads the same on every row.
                Text(record.titleName)
                    .font(.subheadline)
                    .fontWeight(record.isRead ? .regular : .semibold)
                    .foregroundStyle(.primary)

                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
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
