import SwiftUI

/// The last row of a paged list, which asks for the next page by appearing.
///
/// A row of its own rather than an `.onAppear` on the last item: the trigger
/// then does not depend on which item happens to be last, and it survives the
/// list changing underneath it.
struct LoadingMoreRow: View {
    /// Given when the list has stopped asking by itself and is waiting to be
    /// told. A spinner that is not spinning towards anything is a lie.
    var resume: (() -> Void)?

    var body: some View {
        HStack {
            Spacer()

            if let resume {
                Button("Load more", action: resume)
                    .font(.subheadline)
            } else {
                ProgressView()
            }

            Spacer()
        }
        .listRowSeparator(.hidden)
        .accessibilityLabel(resume == nil ? "Loading more" : "Load more")
    }
}
