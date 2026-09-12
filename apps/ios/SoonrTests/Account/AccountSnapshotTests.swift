import Foundation
import SwiftUI
import Testing

@testable import Soonr

/// Layout references for the signed-out account screen: it is the first thing
/// a guest meets, and its button alignment was the reason it was redesigned.
///
/// The signed-in state is not covered. It is a `List`, and `ImageRenderer`
/// draws SwiftUI's unsupported-view placeholder instead of the rows, so a
/// reference would assert nothing.
@MainActor
@Suite(.enabled(if: ViewSnapshot.isSupported))
struct AccountSnapshotTests {
    @Test
    func signedOutOffersASingleFullWidthAction() throws {
        try ViewSnapshot.expect(
            SignedOutAccountContent(signIn: {}),
            named: "Account-SignedOut",
            size: CGSize(width: 390, height: 480)
        )
    }

    @Test
    func signedOutAtAnAccessibilityTextSize() throws {
        try ViewSnapshot.expect(
            SignedOutAccountContent(signIn: {}),
            named: "Account-SignedOut-Accessibility",
            // Generous, because the renderer has no scroll view to grow into:
            // too short a frame makes SwiftUI truncate the labels, which would
            // record a layout bug that the real screen does not have.
            size: CGSize(width: 390, height: 900),
            dynamicTypeSize: .accessibility2
        )
    }
}
