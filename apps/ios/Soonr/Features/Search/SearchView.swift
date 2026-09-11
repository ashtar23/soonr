import SwiftUI

struct SearchView: View {
    @State private var model: SearchModel

    init(
        titleSearch: any TitleSearching = SoonrAPI.live,
        debounceDuration: Duration = .milliseconds(350)
    ) {
        _model = State(
            initialValue: SearchModel(
                titleSearch: titleSearch,
                debounceDuration: debounceDuration
            )
        )
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
            TitleResultRow(title: title)
        }
        .listStyle(.plain)
        .accessibilityLabel("Search results")
    }
}

private struct TitleResultRow: View {
    let title: TitleSummary

    var body: some View {
        HStack(spacing: 14) {
            cover

            VStack(alignment: .leading, spacing: 5) {
                Text(title.name)
                    .font(.headline)
                    .lineLimit(2)

                if let releaseYear = title.releaseYear {
                    Label(releaseYear, systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let platformSummary = title.platformSummary {
                    Text(platformSummary)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var cover: some View {
        Group {
            if let coverImageURL = title.coverImageURL {
                AsyncImage(url: coverImageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        coverPlaceholder
                    @unknown default:
                        coverPlaceholder
                    }
                }
            } else {
                coverPlaceholder
            }
        }
        .frame(width: 68, height: 88)
        .background(.quaternary, in: .rect(cornerRadius: 12))
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityHidden(true)
    }

    private var coverPlaceholder: some View {
        Image(systemName: "photo")
            .font(.title2)
            .foregroundStyle(.secondary)
    }
}

#Preview("Search") {
    SearchView(titleSearch: PreviewTitleSearch())
}

#Preview("Results") {
    NavigationStack {
        SearchResultsList(titles: [.preview])
            .navigationTitle("Search")
    }
}

private struct PreviewTitleSearch: TitleSearching {
    func searchTitles(query: String) async throws -> [TitleSummary] {
        [.preview]
    }
}

private extension TitleSummary {
    static let preview = TitleSummary(
        id: "preview-game",
        kind: "game",
        source: "rawg",
        externalID: "3498",
        slug: "grand-theft-auto-v",
        name: "Grand Theft Auto V",
        coverImageURL: nil,
        earliestReleaseDate: "2013-09-17",
        platforms: [
            TitlePlatform(id: "4", name: "PC"),
            TitlePlatform(id: "18", name: "PlayStation 4"),
            TitlePlatform(id: "1", name: "Xbox One"),
        ],
        rawgRating: 4.47,
        rawgRatingsCount: 7_200,
        rawgMetacritic: 92,
        rawgAdded: 21_000,
        rawgReviewsCount: 690,
        rawgSuggestionsCount: 430,
        rawgRatingTop: 5
    )
}
