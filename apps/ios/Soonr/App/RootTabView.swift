import SwiftUI

struct RootTabView: View {
    @State private var selection: AppTab = .home

    var body: some View {
        if #available(iOS 26, *) {
            tabs
                .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                HomeView()
            }

            Tab("Watchlist", systemImage: "bookmark", value: AppTab.watchlist) {
                WatchlistView()
            }

            Tab("Notifications", systemImage: "bell", value: AppTab.notifications) {
                NotificationsView()
            }

            Tab(
                "Search",
                systemImage: "magnifyingglass",
                value: AppTab.search,
                role: .search
            ) {
                SearchView()
            }

            Tab("Account", systemImage: "person.crop.circle", value: AppTab.account) {
                AccountView()
            }
        }
        .tint(.indigo)
    }
}

#Preview {
    RootTabView()
}
