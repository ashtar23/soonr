import SwiftUI

extension View {
    /// iOS 26 draws this as Liquid Glass; earlier versions fall back to the
    /// bordered style.
    @ViewBuilder
    func prominentButton() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func secondaryButton() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}
