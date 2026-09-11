import SwiftUI

struct WatchlistView: View {
    var body: some View {
        NavigationStack {
            PlaceholderScreen(
                icon: "bookmark",
                title: "Your watchlist",
                description: "Saved games and their upcoming releases will appear here."
            )
            .navigationTitle("Watchlist")
        }
    }
}

#Preview {
    WatchlistView()
}
