import SwiftUI

/// The fill behind an unread row.
///
/// Subtle on purpose: iOS paints a row fill to mean *selected*, so a stronger
/// tint reads as a row you are holding rather than one you have not read. Dark
/// mode needs more of it to register against the darker ground.
struct UnreadRowBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(.tint.opacity(colorScheme == .dark ? 0.16 : 0.08))
    }
}

extension View {
    /// Read rows keep the list's own background, rather than a transparent one
    /// standing in for it, so their highlight on touch is the system's.
    @ViewBuilder
    func unreadRowBackground(_ isUnread: Bool) -> some View {
        if isUnread {
            listRowBackground(UnreadRowBackground())
        } else {
            self
        }
    }
}
