import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            PlaceholderScreen(
                icon: "sparkles",
                title: "Discover what is coming soon",
                description: "Game discovery will appear here in the next slice."
            ) {
                if #available(iOS 26, *) {
                    titleLink
                        .buttonStyle(.glassProminent)
                } else {
                    titleLink
                        .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Home")
        }
    }

    private var titleLink: some View {
        NavigationLink("Open example title") {
            TitleDetailView()
        }
    }
}

#Preview {
    HomeView()
}
