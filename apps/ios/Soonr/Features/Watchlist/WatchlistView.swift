import SwiftUI

struct WatchlistView: View {
    @Environment(SessionStore.self) private var session

    @State private var model: WatchlistModel
    @State private var isPresentingSignIn = false

    private let details: TitleDetailsDependencies

    init(watchlist: any WatchlistManaging, details: TitleDetailsDependencies) {
        _model = State(initialValue: WatchlistModel(watchlist: watchlist))
        self.details = details
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Watchlist")
                .navigationDestination(for: TitleSummary.self) { title in
                    TitleDetailsView(summary: title, dependencies: details)
                }
                .sheet(isPresented: $isPresentingSignIn) {
                    SignInSheet(prompt: "Sign in to see the games you've saved.")
                }
        }
        // Keyed on the session so signing in loads the list and signing out
        // clears it, and so returning to the tab picks up titles saved from
        // the details screen.
        .task(id: session.state) {
            switch session.state {
            case .restoring:
                return
            case .signedOut:
                model.clear()
            case .signedIn:
                await model.load()
            }
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
        switch model.state {
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
                    await model.refresh()
                }
        case let .failed(message):
            ContentUnavailableView {
                Label("Watchlist unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again", systemImage: "arrow.clockwise") {
                    Task {
                        await model.retry()
                    }
                }
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
    WatchlistView(watchlist: PreviewTitleCatalog(), details: .preview)
        .environment(SessionStore(authentication: PreviewAuthentication(restored: .preview)))
}

#Preview("Signed out") {
    WatchlistView(watchlist: PreviewTitleCatalog(), details: .preview)
        .environment(SessionStore(authentication: PreviewAuthentication()))
}

#Preview("Nothing saved") {
    WatchlistView(watchlist: PreviewTitleCatalog(saved: []), details: .preview)
        .environment(SessionStore(authentication: PreviewAuthentication(restored: .preview)))
}
