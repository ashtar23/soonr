import Foundation
import Testing

@testable import Soonr

@MainActor
@Suite(.tags(.networking))
struct HomeModelTests {
    @Test
    func successfulLoadShowsTheRails() async {
        let discovery = HomeDiscovery.fixture(upcoming: [.fixture(name: "Hades II")])
        let model = HomeModel(homeDiscovery: RecordingHomeDiscovery(results: [.success(discovery)]))

        await model.load()

        #expect(model.state == .loaded(discovery))
    }

    @Test
    func railsWithoutTitlesShowTheEmptyState() async {
        let model = HomeModel(
            homeDiscovery: RecordingHomeDiscovery(results: [.success(.fixture())])
        )

        await model.load()

        #expect(model.state == .empty)
    }

    @Test
    func failureShowsItsMessageAndRetryRecovers() async {
        let discovery = HomeDiscovery.fixture(popular: [.fixture(name: "Fable")])
        let loader = RecordingHomeDiscovery(
            results: [.failure(HomeFixtureError.offline), .success(discovery)]
        )
        let model = HomeModel(homeDiscovery: loader)

        await model.load()
        #expect(model.state == .failed(message: "You're offline."))

        await model.retry()
        #expect(model.state == .loaded(discovery))
        #expect(await loader.requestCount == 2)
    }

    @Test
    func loadingAgainAfterSuccessDoesNotRefetch() async {
        let loader = RecordingHomeDiscovery(
            results: [.success(.fixture(latest: [.fixture(name: "Hades")]))]
        )
        let model = HomeModel(homeDiscovery: loader)

        await model.load()
        await model.load()

        #expect(await loader.requestCount == 1)
    }

    @Test
    func refreshRefetchesWithoutClearingTheRails() async {
        let first = HomeDiscovery.fixture(upcoming: [.fixture(name: "Hades II")])
        let second = HomeDiscovery.fixture(upcoming: [.fixture(name: "Fable")])
        let loader = RecordingHomeDiscovery(results: [.success(first), .success(second)])
        let model = HomeModel(homeDiscovery: loader)

        await model.load()
        await model.refresh()

        #expect(model.state == .loaded(second))
        #expect(await loader.requestCount == 2)
    }

    @Test
    func emptyRailsAreDroppedFromPresentation() {
        let discovery = HomeDiscovery.fixture(
            upcoming: [.fixture(name: "Hades II")],
            popular: [.fixture(name: "Fable")]
        )

        #expect(discovery.populatedRails.map(\.section) == [.upcoming, .popular])
        #expect(discovery.isEmpty == false)
    }
}

private actor RecordingHomeDiscovery: HomeDiscovering {
    private(set) var requestCount = 0
    private var results: [Result<HomeDiscovery, HomeFixtureError>]

    init(results: [Result<HomeDiscovery, HomeFixtureError>]) {
        self.results = results
    }

    func homeDiscovery() async throws -> HomeDiscovery {
        requestCount += 1
        let result = results.count > 1 ? results.removeFirst() : results[0]
        return try result.get()
    }
}

private enum HomeFixtureError: Error, LocalizedError, Sendable {
    case offline

    var errorDescription: String? {
        "You're offline."
    }
}

private extension HomeDiscovery {
    static func fixture(
        upcoming: [TitleSummary] = [],
        latest: [TitleSummary] = [],
        popular: [TitleSummary] = []
    ) -> HomeDiscovery {
        HomeDiscovery(upcoming: upcoming, latest: latest, popular: popular)
    }
}

private extension TitleSummary {
    static func fixture(name: String) -> TitleSummary {
        TitleSummary(
            id: "rawg:\(name.hashValue)",
            kind: "game",
            source: "rawg",
            externalID: "1",
            slug: name.lowercased(),
            name: name,
            coverImageURL: nil,
            earliestReleaseDate: "2026-09-25",
            platforms: [],
            rawgRating: nil,
            rawgRatingsCount: nil,
            rawgMetacritic: nil,
            rawgAdded: nil,
            rawgReviewsCount: nil,
            rawgSuggestionsCount: nil,
            rawgRatingTop: nil
        )
    }
}
