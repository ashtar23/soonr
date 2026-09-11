import SwiftUI

/// Remote title artwork with a neutral placeholder. Callers set the size.
struct TitleArtwork: View {
    /// Pixel widths served by RAWG's image CDN. Other widths redirect.
    enum Width: Int, Sendable {
        case thumbnail = 420
        case hero = 1280
    }

    let url: URL?
    let width: Width
    var cornerRadius: CGFloat = 12

    var body: some View {
        // The shape takes exactly the caller's size; the image fills it from an
        // overlay so `scaledToFill` can never grow the layout past that size.
        Rectangle()
            .fill(.quaternary)
            .overlay {
                artwork
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var artwork: some View {
        if let url {
            AsyncImage(
                url: Self.sizedURL(url, width: width),
                transaction: Transaction(animation: .easeOut(duration: 0.2))
            ) { phase in
                switch phase {
                case .empty:
                    Color.clear
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Image(systemName: "gamecontroller")
            .font(.title3)
            .foregroundStyle(.tertiary)
    }

    /// Requests a resized copy from RAWG's CDN instead of the original, which
    /// can be a multi-megapixel image. Other URLs are returned unchanged.
    static func sizedURL(_ url: URL, width: Width) -> URL {
        let mediaPrefix = "/media/"
        let path = url.path(percentEncoded: true)
        guard url.host() == "media.rawg.io", path.hasPrefix(mediaPrefix) else {
            return url
        }

        let assetPath = path.dropFirst(mediaPrefix.count)
        guard assetPath.hasPrefix("resize/") == false,
              assetPath.hasPrefix("crop/") == false,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return url
        }

        components.percentEncodedPath = "\(mediaPrefix)resize/\(width.rawValue)/-/\(assetPath)"
        return components.url ?? url
    }
}
