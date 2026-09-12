import SwiftUI

struct RootTabView: View {
    let dependencies: AppDependencies

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
                homeView
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
                searchView
            }

            Tab("Account", systemImage: "person.crop.circle", value: AppTab.account) {
                AccountView()
            }
        }
    }

    private var legacyTabs: some View {
        TabView(selection: $selection) {
            homeView
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

            searchView
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
    }

    private var homeView: some View {
        HomeView(
            homeDiscovery: dependencies.homeDiscovery,
            titleDetails: dependencies.titleDetails
        )
    }

    private var searchView: some View {
        SearchView(
            titleSearch: dependencies.titleSearch,
            titleDetails: dependencies.titleDetails
        )
    }
}

#Preview {
    RootTabView(dependencies: .preview)
        .environment(ThemeSettings(defaults: .previewDefaults))
}
