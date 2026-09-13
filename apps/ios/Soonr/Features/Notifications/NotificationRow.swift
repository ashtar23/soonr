import SwiftUI

/// One notification as a list row.
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
                // The game, not the event: the server writes a category label
                // ("Release approaching") into `message`, which would read the
                // same on every row and never say which game it is about.
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

    /// What happened and when. `subtitle` carries the detail ("Releases
    /// today"); `message` is the fallback for an event that has none.
    private var caption: String? {
        [record.subtitle ?? record.message, NotificationTimestamp.text(record.createdAt, now: now)]
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
