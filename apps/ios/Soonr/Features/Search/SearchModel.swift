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
            state = .idle
            return
        }

        do {
            if debounced {
                try await ContinuousClock().sleep(for: debounceDuration)
            }

            try Task.checkCancellation()
            state = .loading

            let titles = try await titleSearch.searchTitles(query: normalizedQuery)
            try Task.checkCancellation()
            state = titles.isEmpty ? .empty : .loaded(titles)
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
