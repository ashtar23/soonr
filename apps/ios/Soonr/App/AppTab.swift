enum AppTab: CaseIterable, Hashable, Sendable {
    case home
    case watchlist
    case notifications
    case search
    case account

    var title: String {
        switch self {
        case .home: "Home"
        case .watchlist: "Watchlist"
        case .notifications: "Notifications"
        case .search: "Search"
        case .account: "Account"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .watchlist: "bookmark"
        case .notifications: "bell"
        case .search: "magnifyingglass"
        case .account: "person.crop.circle"
        }
    }
}
