import Foundation
import Testing

@testable import Soonr

extension Tag {
    @Tag static var networking: Self
}

@MainActor
@Suite(.tags(.networking))
struct SearchModelTests {
    @Test
    func successfulSearchLoadsResultsUsingTrimmedQuery() async {
        let search = RecordingTitleSearch(result: .success([.fixture]))
        let model = SearchModel(titleSearch: search, debounceDuration: .zero)
        model.query = "  halo  "

        await model.search()

        #expect(model.state == .loaded([.fixture]))
        #expect(await search.queries == ["halo"])
    }

    @Test
    func shortQueryDoesNotStartARequest() async {
        let search = RecordingTitleSearch(result: .success([.fixture]))
        let model = SearchModel(titleSearch: search, debounceDuration: .zero)
        model.query = "a"

        await model.search()

        #expect(model.state == .idle)
        #expect(await search.queries.isEmpty)
    }

    @Test
    func emptyResponseShowsTheEmptyState() async {
        let model = SearchModel(
            titleSearch: RecordingTitleSearch(result: .success([])),
            debounceDuration: .zero
        )
        model.query = "unknown game"

        await model.search()

        #expect(model.state == .empty)
    }

    @Test
    func serviceFailureShowsItsMessage() async {
        let model = SearchModel(
            titleSearch: RecordingTitleSearch(result: .failure(SearchFixtureError.offline)),
            debounceDuration: .zero
        )
        model.query = "halo"

        await model.search()

        #expect(model.state == .failed(message: "You're offline."))
    }

    @Test
    func searchingTheCompletedQueryAgainKeepsResultsWithoutRefetching() async {
        let search = RecordingTitleSearch(result: .success([.fixture]))
        let model = SearchModel(titleSearch: search, debounceDuration: .zero)
        model.query = "halo"

        await model.search()
        await model.search()

        #expect(model.state == .loaded([.fixture]))
        #expect(await search.queries == ["halo"])
    }

    @Test
    func retryRefetchesTheCompletedQuery() async {
        let search = RecordingTitleSearch(result: .success([.fixture]))
        let model = SearchModel(titleSearch: search, debounceDuration: .zero)
        model.query = "halo"

        await model.search()
        await model.retry()

        #expect(await search.queries == ["halo", "halo"])
    }

    @Test
    func aFailedQueryIsRetriedWhenTheScreenReappears() async {
        let search = RecordingTitleSearch(
            results: [.failure(SearchFixtureError.offline), .success([.fixture])]
        )
        let model = SearchModel(titleSearch: search, debounceDuration: .zero)
        model.query = "halo"

        await model.search()
        #expect(model.state == .failed(message: "You're offline."))

        await model.search()

        #expect(model.state == .loaded([.fixture]))
    }
}

private actor RecordingTitleSearch: TitleSearching {
    private(set) var queries: [String] = []
    private var results: [Result<[TitleSummary], SearchFixtureError>]

    /// Answers every request with the same result.
    init(result: Result<[TitleSummary], SearchFixtureError>) {
        self.results = [result]
    }

    /// Answers requests in order, repeating the last result.
    init(results: [Result<[TitleSummary], SearchFixtureError>]) {
        self.results = results
    }

    func searchTitles(query: String) async throws -> [TitleSummary] {
        queries.append(query)
        let result = results.count > 1 ? results.removeFirst() : results[0]
        return try result.get()
    }
}

private enum SearchFixtureError: Error, LocalizedError, Sendable {
    case offline

    var errorDescription: String? {
        "You're offline."
    }
}

private extension TitleSummary {
    static let fixture = TitleSummary(
        id: "halo-infinite",
        kind: "game",
        source: "rawg",
        externalID: "58777",
        slug: "halo-infinite",
        name: "Halo Infinite",
        coverImageURL: nil,
        earliestReleaseDate: "2021-12-08",
        platforms: [TitlePlatform(id: "4", name: "PC")],
        rawgRating: 3.94,
        rawgRatingsCount: 900,
        rawgMetacritic: 87,
        rawgAdded: 9_000,
        rawgReviewsCount: 80,
        rawgSuggestionsCount: 320,
        rawgRatingTop: 5
    )
}
