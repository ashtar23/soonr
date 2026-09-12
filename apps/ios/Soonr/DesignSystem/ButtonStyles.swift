import SwiftUI

extension View {
    /// The filled style for a screen's single main action. iOS 26 draws it as
    /// Liquid Glass; earlier versions fall back to the bordered style.
    @ViewBuilder
    func prominentButton() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// A bordered action that sits beside, but below, a prominent one.
    @ViewBuilder
    func secondaryButton() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}
