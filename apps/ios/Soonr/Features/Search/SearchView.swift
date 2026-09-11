import SwiftUI

struct SearchView: View {
    @State private var model: SearchModel

    private let titleDetails: any TitleDetailsLoading

    init(
        titleSearch: any TitleSearching,
        titleDetails: any TitleDetailsLoading,
        debounceDuration: Duration = .milliseconds(350)
    ) {
        _model = State(
            initialValue: SearchModel(
                titleSearch: titleSearch,
                debounceDuration: debounceDuration
            )
        )
        self.titleDetails = titleDetails
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
                .navigationDestination(for: TitleSummary.self) { title in
                    TitleDetailsView(summary: title, titleDetails: titleDetails)
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
        case let .failed(message):
            ContentUnavailableView {
                Label("Search unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again", systemImage: "arrow.clockwise") {
                    Task {
                        await retry()
                    }
                }
            }
        }
    }
}

private struct SearchResultsList: View {
    let titles: [TitleSummary]

    var body: some View {
        List(titles) { title in
            NavigationLink(value: title) {
                TitleResultRow(title: title)
            }
            // Plain lists also draw separators above the first row and below
            // the last one; separators belong between results only.
            .listRowSeparator(title.id == titles.first?.id ? .hidden : .automatic, edges: .top)
            .listRowSeparator(title.id == titles.last?.id ? .hidden : .automatic, edges: .bottom)
        }
        .listStyle(.plain)
        .accessibilityLabel("Search results")
    }
}

private struct TitleResultRow: View {
    let title: TitleSummary

    var body: some View {
        let daysUntilRelease = ReleaseDateText.daysUntil(title.earliestReleaseDate)

        HStack(spacing: 12) {
            // RAWG artwork is landscape, so the thumbnail keeps a 16:9 shape.
            TitleArtwork(url: title.coverImageURL, width: .thumbnail, cornerRadius: 8)
                .frame(width: 104, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(title.name)
                    .font(.headline)
                    .lineLimit(2)

                Text(metadata(daysUntilRelease: daysUntilRelease))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let countdown = daysUntilRelease.flatMap(ReleaseDateText.countdown) {
                    Text(countdown)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: .capsule)
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { dimensions in
                dimensions[.leading]
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// Upcoming releases show the full date; past releases show the year.
    private func metadata(daysUntilRelease: Int?) -> String {
        let releaseText = if let daysUntilRelease, daysUntilRelease >= 0 {
            ReleaseDateText.format(title.earliestReleaseDate, precision: .day)
        } else {
            title.releaseYear ?? ReleaseDateText.unannounced
        }

        return [releaseText, title.platformSummary]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

#Preview("Search") {
    SearchView(
        titleSearch: PreviewTitleCatalog(),
        titleDetails: PreviewTitleCatalog()
    )
}

#Preview("Results") {
    NavigationStack {
        SearchResultsList(titles: PreviewTitleCatalog().results)
            .navigationTitle("Search")
    }
}
