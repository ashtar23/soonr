import SwiftUI

struct SearchView: View {
    @State private var model: SearchModel

    private let details: TitleDetailsDependencies

    init(
        titleSearch: any TitleSearching,
        details: TitleDetailsDependencies,
        debounceDuration: Duration = .milliseconds(350)
    ) {
        _model = State(
            initialValue: SearchModel(
                titleSearch: titleSearch,
                debounceDuration: debounceDuration
            )
        )
        self.details = details
    }

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            searchContent
                .navigationTitle("Search")
                .searchable(text: $model.query, prompt: "Search games")
                .task(id: model.query) {
                    await model.search()
                }
                .navigationDestination(for: TitleDestination.self) { destination in
                    TitleDetailsView(destination: destination, dependencies: details)
                }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        let content = SearchContent(
            state: model.state,
            query: model.query,
            retry: {
                await model.retry()
            }
        )

        if #available(iOS 26, *) {
            content.searchToolbarBehavior(.minimize)
        } else {
            content
        }
    }
}

private struct SearchContent: View {
    let state: SearchState
    let query: String
    let retry: () async -> Void

    var body: some View {
        switch state {
        case .idle:
            ContentUnavailableView(
                "Find a game",
                systemImage: "magnifyingglass",
                description: Text("Enter at least two characters to search Soonr.")
            )
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Searching…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        case let .loaded(titles):
            SearchResultsList(titles: titles)
        case .empty:
            ContentUnavailableView.search(text: query)
        case let .failed(reason):
            FailureView(title: "Search unavailable", reason: reason) {
                await retry()
            }
        }
    }
}

private struct SearchResultsList: View {
    let titles: [TitleSummary]

    var body: some View {
        List(titles) { title in
            NavigationLink(value: TitleDestination(title)) {
                TitleRow(title: title)
            }
            .hidingOuterSeparators(
                isFirst: title.id == titles.first?.id,
                isLast: title.id == titles.last?.id
            )
        }
        .listStyle(.plain)
        .accessibilityLabel("Search results")
    }
}

#if DEBUG

    #Preview("Search") {
        SearchView(
            titleSearch: PreviewTitleCatalog(),
            details: .preview
        )
        .environment(SessionStore(authentication: PreviewAuthentication(restored: .preview)))
    }

    #Preview("Results") {
        NavigationStack {
            SearchResultsList(titles: PreviewTitleCatalog().results)
                .navigationTitle("Search")
        }
    }

#endif
