import Foundation
import Observation

enum SearchState: Equatable {
    case idle
    case loading
    case loaded([TitleSummary])
    case empty
    case failed(message: String)
}

@MainActor
@Observable
final class SearchModel {
    var query = ""
    private(set) var state: SearchState = .idle

    @ObservationIgnored private let titleSearch: any TitleSearching
    @ObservationIgnored private let debounceDuration: Duration
    /// The query whose results are currently shown. SwiftUI restarts
    /// `.task(id:)` whenever the screen reappears, such as after switching
    /// tabs; this keeps that from refetching unchanged results.
    @ObservationIgnored private var completedQuery: String?

    init(
        titleSearch: any TitleSearching,
        debounceDuration: Duration = .milliseconds(350)
    ) {
        self.titleSearch = titleSearch
        self.debounceDuration = debounceDuration
    }

    func search() async {
        await load(debounced: true)
    }

    func retry() async {
        await load(debounced: false)
    }

    private func load(debounced: Bool) async {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedQuery.count >= 2 else {
            completedQuery = nil
            state = .idle
            return
        }

        if debounced, normalizedQuery == completedQuery {
            return
        }

        do {
            if debounced {
                try await ContinuousClock().sleep(for: debounceDuration)
            }

            try Task.checkCancellation()
            completedQuery = nil
            state = .loading

            let titles = try await titleSearch.searchTitles(query: normalizedQuery)
            try Task.checkCancellation()
            state = titles.isEmpty ? .empty : .loaded(titles)
            completedQuery = normalizedQuery
        } catch is CancellationError {
            return
        } catch {
            state = .failed(
                message: error.localizedDescription.isEmpty
                    ? "Search failed. Please try again."
                    : error.localizedDescription
            )
        }
    }
}
