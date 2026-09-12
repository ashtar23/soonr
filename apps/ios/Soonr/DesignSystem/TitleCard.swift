import SwiftUI

/// A title as an artwork-led card for horizontal discovery rails.
struct TitleCard: View {
    let title: TitleSummary
    var now: Date = .now

    /// Cards grow with the text they carry so the name keeps room to breathe.
    @ScaledMetric(relativeTo: .headline) private var cardWidth: CGFloat = 200

    var body: some View {
        let daysUntilRelease = ReleaseDateText.daysUntil(title.earliestReleaseDate, now: now)

        VStack(alignment: .leading, spacing: 8) {
            TitleArtwork(url: title.coverImageURL, width: .thumbnail, cornerRadius: 12)
                .frame(width: cardWidth, height: cardWidth * 9 / 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(title.name)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(
                    TitleRowText.metadata(
                        for: title,
                        daysUntilRelease: daysUntilRelease,
                        showsPlatforms: false
                    )
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if let countdown = daysUntilRelease.flatMap(ReleaseDateText.countdown) {
                    ReleaseBadge(text: countdown)
                }
            }
            // A fixed height keeps card bottoms aligned when names wrap to one
            // line in one card and two in the next.
            .frame(width: cardWidth, height: cardTextHeight, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
    }

    @ScaledMetric(relativeTo: .headline) private var cardTextHeight: CGFloat = 84
}

#Preview("Cards") {
    ScrollView(.horizontal) {
        HStack(alignment: .top, spacing: 16) {
            TitleCard(title: .previewUpcoming)
            TitleCard(title: .preview)
        }
        .padding()
    }
}
