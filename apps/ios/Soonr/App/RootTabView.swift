import SwiftUI

struct RootTabView: View {
    let dependencies: AppDependencies

    @Environment(NotificationsStore.self) private var notifications
    @Environment(AppRouter.self) private var router

    var body: some View {
        tabs(selection: tabSelection)
    }

    /// Every selection, including re-tapping the tab already showing, which
    /// the router reads as a request to go back to the top.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { router.selectedTab },
            set: { router.select($0) }
        )
    }

    @ViewBuilder
    private func tabs(selection: Binding<AppTab>) -> some View {
        if #available(iOS 26, *) {
            modernTabs(selection: selection)
                .tabBarMinimizeBehavior(.onScrollDown)
        } else if #available(iOS 18, *) {
            modernTabs(selection: selection)
        } else {
            legacyTabs(selection: selection)
        }
    }

    @available(iOS 18, *)
    private func modernTabs(selection: Binding<AppTab>) -> some View {
        TabView(selection: selection) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                homeView
            }

            Tab("Watchlist", systemImage: "bookmark", value: AppTab.watchlist) {
                watchlistView
            }

            Tab("Notifications", systemImage: "bell", value: AppTab.notifications) {
                notificationsView
            }
            .badge(notifications.unreadCount)

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

    private func legacyTabs(selection: Binding<AppTab>) -> some View {
        TabView(selection: selection) {
            homeView
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(AppTab.home)

            watchlistView
                .tabItem {
                    Label("Watchlist", systemImage: "bookmark")
                }
                .tag(AppTab.watchlist)

            notificationsView
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
                .badge(notifications.unreadCount)
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
            details: dependencies.titleDetails
        )
    }

    private var notificationsView: some View {
        NotificationsView(details: dependencies.titleDetails)
    }

    private var watchlistView: some View {
        WatchlistView(details: dependencies.titleDetails)
    }

    private var searchView: some View {
        SearchView(
            titleSearch: dependencies.titleSearch,
            details: dependencies.titleDetails
        )
    }
}

#if DEBUG

    #Preview {
        RootTabView(dependencies: .preview)
            .environment(ThemeSettings(defaults: .previewDefaults))
            .environment(NotificationsStore(notifications: PreviewNotifications()))
    }

#endif
