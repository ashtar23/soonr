import SwiftUI

/// A title as a list row: artwork, name, release and platform metadata, and a
/// countdown badge for releases that are today or ahead. Shared by search and,
/// from the discovery slice, Home.
struct TitleRow: View {
    let title: TitleSummary
    var now: Date = .now

    /// Grows with the title's text so artwork and text stay in proportion,
    /// capped so accessibility sizes do not leave the name a narrow column.
    @ScaledMetric(relativeTo: .headline) private var artworkWidth: CGFloat = 104
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var thumbnailWidth: CGFloat {
        min(artworkWidth, 148)
    }

    var body: some View {
        let daysUntilRelease = ReleaseDateText.daysUntil(title.earliestReleaseDate, now: now)
        // Side by side leaves the name a narrow, hyphenated column once text
        // reaches accessibility sizes, so the row stacks instead.
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))

        layout {
            // RAWG artwork is landscape, so the thumbnail keeps a 16:9 shape.
            TitleArtwork(url: title.coverImageURL, width: .thumbnail, cornerRadius: 8)
                .frame(width: thumbnailWidth, height: thumbnailWidth * 9 / 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(title.name)
                    .font(.headline)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)

                Text(TitleRowText.metadata(for: title, daysUntilRelease: daysUntilRelease))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)

                if let countdown = daysUntilRelease.flatMap(ReleaseDateText.countdown) {
                    ReleaseBadge(text: countdown)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .alignmentGuide(.listRowSeparatorLeading) { dimensions in
                dimensions[.leading]
            }
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
    ///
    /// Platforms disambiguate similarly named search results, but on a
    /// discovery card they truncate to "PlayStation…", so cards omit them.
    static func metadata(
        for title: TitleSummary,
        daysUntilRelease: Int?,
        showsPlatforms: Bool = true
    ) -> String {
        let releaseText =
            if let daysUntilRelease, daysUntilRelease >= 0 {
                ReleaseDateText.format(title.earliestReleaseDate, precision: .day)
            } else {
                title.releaseYear ?? ReleaseDateText.unannounced
            }

        return [releaseText, showsPlatforms ? title.platformSummary : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

#Preview("Default type size") {
    List {
        TitleRow(title: .previewUpcoming)
        TitleRow(title: .preview)
    }
    .listStyle(.plain)
}

#Preview("Accessibility type size") {
    List {
        TitleRow(title: .previewUpcoming)
        TitleRow(title: .preview)
    }
    .listStyle(.plain)
    .dynamicTypeSize(.accessibility3)
}
