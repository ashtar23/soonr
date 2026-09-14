import SwiftUI

/// One row of a list about a title: artwork, a name, a line about it, and
/// whatever the list adds beside them.
///
/// What varies between lists is what the second line says and what hangs off
/// the end. The shape, the type ramp and the spacing do not, which is what
/// makes the same game look like the same game wherever it appears.
struct TitleListRow<Accessory: View>: View {
    let artworkURL: URL?
    let title: String
    let secondary: String?
    /// Left alone unless a list has something to say with it, the way an
    /// unread notification does.
    var titleWeight: Font.Weight?
    @ViewBuilder var accessory: () -> Accessory

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Grows with the title's text so artwork and text stay in proportion,
    /// capped so accessibility sizes do not leave the name a narrow column.
    @ScaledMetric(relativeTo: .headline) private var scaledArtwork: CGFloat = 104

    var body: some View {
        // Side by side leaves the name a narrow, hyphenated column once text
        // reaches accessibility sizes, so the row stacks instead — keeping the
        // artwork, which is what makes a list of similar names scannable.
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))

        layout {
            // RAWG artwork is landscape, so the thumbnail keeps a 16:9 shape.
            TitleArtwork(url: artworkURL, width: .thumbnail, cornerRadius: 8)
                .frame(width: artworkWidth, height: artworkWidth * 9 / 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(titleWeight)
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)

                if let secondary {
                    Text(secondary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                }

                accessory()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .alignmentGuide(.listRowSeparatorLeading) { dimensions in
                dimensions[.leading]
            }
        }
        .padding(.vertical, 4)
    }

    private var artworkWidth: CGFloat {
        min(scaledArtwork, 148)
    }
}

extension TitleListRow where Accessory == EmptyView {
    init(
        artworkURL: URL?,
        title: String,
        secondary: String?,
        titleWeight: Font.Weight? = nil
    ) {
        self.init(
            artworkURL: artworkURL,
            title: title,
            secondary: secondary,
            titleWeight: titleWeight,
            accessory: { EmptyView() }
        )
    }
}
