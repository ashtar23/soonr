import SwiftUI

extension View {
    /// A plain list draws a separator above the first row and below the last,
    /// which read as stray rules under a large title and above the tab bar
    /// rather than as dividers between rows.
    func hidingOuterSeparators(isFirst: Bool, isLast: Bool) -> some View {
        self
            .listRowSeparator(.hidden, edges: isFirst ? .top : [])
            .listRowSeparator(.hidden, edges: isLast ? .bottom : [])
    }
}
