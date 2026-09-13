import SwiftUI

/// A spinner filling the space a screen's content will take.
struct LoadingScreen: View {
    var body: some View {
        ProgressView()
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
