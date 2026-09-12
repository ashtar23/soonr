import SwiftUI

/// A title as a list row: artwork, name, release and platform metadata, and a
/// countdown badge for releases that are today or ahead. Shared by search and,
/// from the discovery slice, Home.
struct TitleRow: View {
    let title: TitleSummary
    var now: Date = .now

    var body: some View {
        let daysUntilRelease = ReleaseDateText.daysUntil(title.earliestReleaseDate, now: now)

        HStack(spacing: 12) {
            // RAWG artwork is landscape, so the thumbnail keeps a 16:9 shape.
            TitleArtwork(url: title.coverImageURL, width: .thumbnail, cornerRadius: 8)
                .frame(width: 104, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(title.name)
                    .font(.headline)
                    .lineLimit(2)

                Text(TitleRowText.metadata(for: title, daysUntilRelease: daysUntilRelease))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let countdown = daysUntilRelease.flatMap(ReleaseDateText.countdown) {
                    ReleaseBadge(text: countdown)
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { dimensions in
                dimensions[.leading]
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// A tinted capsule for a release countdown.
struct ReleaseBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.tint.opacity(0.15), in: .capsule)
    }
}

enum TitleRowText {
    /// Upcoming releases show the full date; past releases show the year.
    static func metadata(for title: TitleSummary, daysUntilRelease: Int?) -> String {
        let releaseText =
            if let daysUntilRelease, daysUntilRelease >= 0 {
                ReleaseDateText.format(title.earliestReleaseDate, precision: .day)
            } else {
                title.releaseYear ?? ReleaseDateText.unannounced
            }

        return [releaseText, title.platformSummary]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

#Preview {
    List {
        TitleRow(title: .previewUpcoming)
        TitleRow(title: .preview)
    }
    .listStyle(.plain)
}
