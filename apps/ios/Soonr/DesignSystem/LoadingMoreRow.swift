import SwiftUI

/// The last row of a paged list, which asks for the next page by appearing.
///
/// A row of its own rather than an `.onAppear` on the last item: the trigger
/// then does not depend on which item happens to be last, and it survives the
/// list changing underneath it.
struct LoadingMoreRow: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .listRowSeparator(.hidden)
        .accessibilityLabel("Loading more")
    }
}
