import SwiftUI

extension View {
    /// Hides the separator above the first row and below the last one.
    ///
    /// A plain list draws both, which read as stray rules under a large
    /// navigation title and above the tab bar rather than as dividers between
    /// rows.
    func hidingOuterSeparators(isFirst: Bool, isLast: Bool) -> some View {
        self
            .listRowSeparator(.hidden, edges: isFirst ? .top : [])
            .listRowSeparator(.hidden, edges: isLast ? .bottom : [])
    }
}
