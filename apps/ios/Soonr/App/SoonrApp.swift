import SwiftUI

@main
struct SoonrApp: App {
    private let dependencies: AppDependencies

    @State private var theme = ThemeSettings()
    @State private var session: SessionStore
    @State private var watchlist: WatchlistStore

    init() {
        let dependencies = AppDependencies.live()
        self.dependencies = dependencies
        _session = State(initialValue: SessionStore(authentication: dependencies.authentication))
        _watchlist = State(initialValue: WatchlistStore(watchlist: dependencies.watchlist))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(dependencies: dependencies)
                .environment(theme)
                .environment(session)
                .environment(watchlist)
                .tint(theme.accent.color)
                .preferredColorScheme(theme.appearance.colorScheme)
                .task {
                    await session.restore()
                }
                // Loaded as soon as there is a session, so a bookmark is
                // already known by the time any title is opened, and dropped on
                // sign out rather than left for the next account.
                .task(id: session.state) {
                    switch session.state {
                    case .restoring:
                        return
                    case .signedOut:
                        watchlist.clear()
                    case .signedIn:
                        await watchlist.load()
                    }
                }
        }
    }
}
