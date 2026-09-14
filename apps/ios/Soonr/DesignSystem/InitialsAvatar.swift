import SwiftUI

/// Somebody, as a circle.
///
/// Initials on a tint rather than a grey silhouette: every account has a name
/// of some kind, so the placeholder can say who it belongs to instead of
/// saying that a picture is missing.
struct InitialsAvatar: View {
    let name: String
    var diameter: CGFloat = 44

    var body: some View {
        Circle()
            .fill(.tint.opacity(0.15))
            .frame(width: diameter, height: diameter)
            .overlay {
                Text(Self.initials(for: name))
                    .font(.system(size: diameter * 0.36, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            .accessibilityHidden(true)
    }

    /// The first letter or digit of each of the first two words, which is a
    /// person's initials for a name and something recognisable for anything
    /// else. Punctuation is skipped, so a handle does not come out as "@".
    ///
    /// `nonisolated` because `View` is main-actor isolated, which its static
    /// members inherit; without it this string arithmetic can only be called
    /// from the main actor, and a test that did so trapped at runtime.
    nonisolated static func initials(for name: String) -> String {
        let letters =
            name
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap { word in
                word.first { $0.isLetter || $0.isNumber }
            }

        guard letters.isEmpty == false else {
            return "?"
        }

        return String(letters).uppercased()
    }
}

#if DEBUG

    #Preview("Initials") {
        HStack(spacing: 16) {
            InitialsAvatar(name: "Vladimir Turkonja")
            InitialsAvatar(name: "reader")
            InitialsAvatar(name: "you@example.com")
            InitialsAvatar(name: "")
        }
        .padding()
    }

#endif
