import SwiftUI

struct WatchlistView: View {
    @Environment(SessionStore.self) private var session
    @Environment(WatchlistStore.self) private var watchlist

    @State private var isPresentingSignIn = false

    private let details: TitleDetailsDependencies

    init(details: TitleDetailsDependencies) {
        self.details = details
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Watchlist")
                .navigationDestination(for: TitleDestination.self) { destination in
                    TitleDetailsView(destination: destination, dependencies: details)
                }
        }
        // Attached to the stack, not to `content`: signing in switches that
        // view, and a sheet attached to it is torn off without animating.
        .sheet(isPresented: $isPresentingSignIn) {
            SignInSheet(prompt: "Sign in to see the games you've saved.")
        }
        // The root loads the store once and never again, which left a failed
        // load with no way back except the retry button. An already-loaded
        // list is left alone, so this costs nothing in the normal case.
        .task {
            guard case .signedIn = session.state, watchlist.state.entries == nil else {
                return
            }

            await watchlist.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.state {
        case .restoring:
            LoadingScreen()
        case .signedOut:
            PlaceholderScreen(
                icon: "bookmark",
                title: "Your watchlist",
                description: "Sign in to see the games you've saved and when they arrive."
            ) {
                Button("Sign in") {
                    isPresentingSignIn = true
                }
                .prominentButton()
                .controlSize(.large)
            }
        case .signedIn:
            signedInContent
        }
    }

    @ViewBuilder
    private var signedInContent: some View {
        switch watchlist.state {
        case .loading:
            LoadingScreen()
        case let .loaded(entries) where entries.isEmpty:
            PlaceholderScreen(
                icon: "bookmark",
                title: "Nothing saved yet",
                description: "Open a game and tap the bookmark to follow its release."
            )
        case let .loaded(entries):
            WatchlistList(entries: entries)
                .refreshable {
                    await watchlist.refresh()
                }
        case let .failed(reason):
            FailureView(title: "Watchlist unavailable", reason: reason) {
                await watchlist.retry()
            }
        }
    }
}

private struct WatchlistList: View {
    let entries: [WatchlistEntry]

    @Environment(WatchlistStore.self) private var watchlist

    var body: some View {
        ScrollToTop(tab: .watchlist) {
            list
        }
    }

    private var list: some View {
        List {
            ScrollToTopAnchor()

            ForEach(entries) { entry in
                NavigationLink(value: TitleDestination(entry.title)) {
                    TitleRow(title: entry.title)
                }
                .hidingOuterSeparators(
                    isFirst: entry.id == entries.first?.id,
                    isLast: entry.id == entries.last?.id
                )
            }

            // A row of its own rather than an `.onAppear` on the last entry, so
            // the trigger does not depend on which entry happens to be last.
            if watchlist.hasMore {
                LoadingMoreRow()
                    .task {
                        await watchlist.loadMore()
                    }
            }
        }
        .listStyle(.plain)
        .accessibilityLabel("Saved games")
    }
}

#if DEBUG

    #Preview("Saved games") {
        WatchlistPreview(catalog: PreviewTitleCatalog(), restored: .preview)
    }

    #Preview("Signed out") {
        WatchlistPreview(catalog: PreviewTitleCatalog(), restored: nil)
    }

    #Preview("Nothing saved") {
        WatchlistPreview(catalog: PreviewTitleCatalog(saved: []), restored: .preview)
    }

    /// Loads the store the way the app root does, so previews show the states a
    /// signed-in viewer would see.
    private struct WatchlistPreview: View {
        let catalog: PreviewTitleCatalog
        let restored: UserSession?

        @State private var watchlist: WatchlistStore
        @State private var session: SessionStore

        init(catalog: PreviewTitleCatalog, restored: UserSession?) {
            self.catalog = catalog
            self.restored = restored
            _watchlist = State(initialValue: WatchlistStore(watchlist: catalog))
            _session = State(
                initialValue: SessionStore(
                    authentication: PreviewAuthentication(restored: restored))
            )
        }

        var body: some View {
            WatchlistView(details: .preview)
                .environment(session)
                .environment(watchlist)
                .task {
                    await session.restore()
                    await watchlist.load()
                }
        }
    }

#endif
