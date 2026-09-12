import Foundation
import Testing

@testable import Soonr

@MainActor
@Suite(.tags(.networking))
struct WatchlistModelTests {
    @Test
    func loadShowsSavedTitles() async {
        let model = WatchlistModel(watchlist: StubWatchlist(results: [.success([.fixture])]))

        await model.load()

        #expect(model.state == .loaded([.fixture]))
    }

    @Test
    func anEmptyWatchlistLoadsAsAnEmptyList() async {
        let model = WatchlistModel(watchlist: StubWatchlist(results: [.success([])]))

        await model.load()

        #expect(model.state == .loaded([]))
    }

    @Test
    func failureShowsItsMessageAndRetryRecovers() async {
        let model = WatchlistModel(
            watchlist: StubWatchlist(results: [
                .failure(.offline),
                .success([.fixture]),
            ])
        )

        await model.load()
        #expect(model.state == .failed(message: "You're offline."))

        await model.retry()
        #expect(model.state == .loaded([.fixture]))
    }

    /// Titles are saved from the details screen, so the tab has to refetch when
    /// it reappears rather than trusting what it already has.
    @Test
    func loadingAgainRefetches() async {
        let watchlist = StubWatchlist(results: [.success([]), .success([.fixture])])
        let model = WatchlistModel(watchlist: watchlist)

        await model.load()
        await model.load()

        #expect(model.state == .loaded([.fixture]))
        #expect(await watchlist.loads == 2)
    }

    @Test
    func refreshReplacesTheListWithWhatTheServerNowHas() async {
        let model = WatchlistModel(
            watchlist: StubWatchlist(results: [.success([.fixture]), .success([])])
        )
        await model.load()

        await model.refresh()

        #expect(model.state == .loaded([]))
    }

    @Test
    func signingOutClearsAnotherAccountsTitles() async {
        let model = WatchlistModel(watchlist: StubWatchlist(results: [.success([.fixture])]))
        await model.load()

        model.clear()

        #expect(model.state == .loaded([]))
    }
}

private actor StubWatchlist: WatchlistManaging {
    private(set) var loads = 0
    private var results: [Result<[WatchlistEntry], WatchlistFixtureError>]

    init(results: [Result<[WatchlistEntry], WatchlistFixtureError>]) {
        self.results = results
    }

    func watchlist() async throws -> [WatchlistEntry] {
        loads += 1
        return try results.removeFirst().get()
    }

    func addToWatchlist(titleID: String) async throws {}

    func removeFromWatchlist(titleID: String) async throws {}
}

private extension WatchlistEntry {
    static let fixture = WatchlistEntry(
        id: "watchlist-1",
        title: .preview,
        addedAt: "2026-01-01T10:00:00Z"
    )
}

private enum WatchlistFixtureError: Error, LocalizedError, Sendable {
    case offline

    var errorDescription: String? {
        "You're offline."
    }
}
