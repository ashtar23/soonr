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
                .navigationDestination(for: TitleSummary.self) { title in
                    TitleDetailsView(summary: title, dependencies: details)
                }
        }
        // Attached to the stack, not to `content`: signing in switches that
        // view, and a sheet attached to it is torn off without animating.
        .sheet(isPresented: $isPresentingSignIn) {
            SignInSheet(prompt: "Sign in to see the games you've saved.")
        }
        // The root loads the store once so a bookmark is known before any
        // title is opened, but the root appears once and never again, which
        // left a failed load with no way back except the retry button. Opening
        // the tab tries again; an already-loaded list is left alone, so this
        // costs nothing in the normal case.
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
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    var body: some View {
        List {
            ForEach(entries) { entry in
                NavigationLink(value: entry.title) {
                    TitleRow(title: entry.title)
                }
                .listRowSeparator(.hidden, edges: entry.id == entries.first?.id ? .top : [])
                .listRowSeparator(.hidden, edges: entry.id == entries.last?.id ? .bottom : [])
            }
        }
        .listStyle(.plain)
        .accessibilityLabel("Saved games")
    }
}

#Preview("Saved games") {
    WatchlistPreview(catalog: PreviewTitleCatalog(), restored: .preview)
}

#Preview("Signed out") {
    WatchlistPreview(catalog: PreviewTitleCatalog(), restored: nil)
}

#Preview("Nothing saved") {
    WatchlistPreview(catalog: PreviewTitleCatalog(saved: []), restored: .preview)
}

/// Loads the store the way the app root does, so the previews show the states
/// a signed-in viewer would actually see.
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
            initialValue: SessionStore(authentication: PreviewAuthentication(restored: restored))
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
