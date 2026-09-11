import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            PlaceholderScreen(
                icon: "sparkles",
                title: "Discover what is coming soon",
                description:
                    "Upcoming, latest, and popular games will appear here in a later slice."
            )
            .navigationTitle("Home")
        }
    }
}

#Preview {
    HomeView()
}
