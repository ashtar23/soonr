import SwiftUI

struct TitleRow: View {
    let title: TitleSummary
    var now: Date = .now

    var body: some View {
        let daysUntilRelease = ReleaseDateText.daysUntil(title.earliestReleaseDate, now: now)

        TitleListRow(
            artworkURL: title.coverImageURL,
            title: title.name,
            secondary: TitleRowText.metadata(for: title, daysUntilRelease: daysUntilRelease)
        ) {
            if let countdown = daysUntilRelease.flatMap(ReleaseDateText.countdown) {
                ReleaseBadge(text: countdown)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

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

#if DEBUG

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

#endif
