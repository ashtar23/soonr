import SwiftUI

struct RootTabView: View {
    @State private var selection: AppTab = .home

    var body: some View {
        if #available(iOS 26, *) {
            modernTabs
                .tabBarMinimizeBehavior(.onScrollDown)
        } else if #available(iOS 18, *) {
            modernTabs
        } else {
            legacyTabs
        }
    }

    @available(iOS 18, *)
    private var modernTabs: some View {
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

    private var legacyTabs: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(AppTab.home)

            WatchlistView()
                .tabItem {
                    Label("Watchlist", systemImage: "bookmark")
                }
                .tag(AppTab.watchlist)

            NotificationsView()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
                .tag(AppTab.notifications)

            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(AppTab.search)

            AccountView()
                .tabItem {
                    Label("Account", systemImage: "person.crop.circle")
                }
                .tag(AppTab.account)
        }
        .tint(.indigo)
    }
}

#Preview {
    RootTabView()
}
