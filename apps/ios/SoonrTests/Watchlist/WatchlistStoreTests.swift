import Foundation
import Testing

@testable import Soonr

@MainActor
@Suite(.tags(.networking))
struct WatchlistStoreTests {
    @Test
    func loadShowsSavedTitlesAndTheirMembership() async {
        let store = WatchlistStore(watchlist: StubWatchlist(results: [.success([.fixture])]))

        await store.load()

        #expect(store.state == .loaded([.fixture]))
        #expect(store.contains(TitleSummary.preview.id))
    }

    @Test
    func anEmptyWatchlistLoadsAsAnEmptyList() async {
        let store = WatchlistStore(watchlist: StubWatchlist(results: [.success([])]))

        await store.load()

        #expect(store.state == .loaded([]))
        #expect(store.contains(TitleSummary.preview.id) == false)
    }

    @Test
    func failureShowsItsMessageAndRetryRecovers() async {
        let store = WatchlistStore(
            watchlist: StubWatchlist(results: [.failure(.offline), .success([.fixture])])
        )

        await store.load()
        #expect(store.state == .failed(message: "You're offline."))

        await store.retry()
        #expect(store.state == .loaded([.fixture]))
    }

    @Test
    func refreshReplacesTheListWithWhatTheServerNowHas() async {
        let store = WatchlistStore(
            watchlist: StubWatchlist(results: [.success([.fixture]), .success([])])
        )
        await store.load()

        await store.refresh()

        #expect(store.state == .loaded([]))
        #expect(store.contains(TitleSummary.preview.id) == false)
    }

    /// The reason the store exists: removing a title from the details screen
    /// has to empty the tab without anyone refetching.
    @Test
    func removingATitleDropsItFromTheListImmediately() async {
        let watchlist = StubWatchlist(results: [.success([.fixture])])
        let store = WatchlistStore(watchlist: watchlist)
        await store.load()

        await store.setSaved(false, title: .preview)

        #expect(store.state == .loaded([]))
        #expect(store.contains(TitleSummary.preview.id) == false)
        #expect(await watchlist.changes == [.removed(TitleSummary.preview.id)])
    }

    @Test
    func savingATitleAddsItToTheTopOfTheList() async {
        let watchlist = StubWatchlist(results: [.success([])])
        let store = WatchlistStore(watchlist: watchlist)
        await store.load()

        await store.setSaved(true, title: .preview)

        #expect(store.contains(TitleSummary.preview.id))
        #expect(store.state.entries?.map(\.title.id) == [TitleSummary.preview.id])
        #expect(await watchlist.changes == [.added(TitleSummary.preview.id)])
    }

    @Test
    func aRejectedSaveRollsBackTheListAndReportsWhy() async {
        let store = WatchlistStore(
            watchlist: StubWatchlist(results: [.success([])], failingMutations: true)
        )
        await store.load()

        await store.setSaved(true, title: .preview)

        #expect(store.state == .loaded([]))
        #expect(store.contains(TitleSummary.preview.id) == false)
        #expect(store.mutationFailure == "You're offline.")
    }

    @Test
    func aRejectedRemovalPutsTheTitleBack() async {
        let store = WatchlistStore(
            watchlist: StubWatchlist(results: [.success([.fixture])], failingMutations: true)
        )
        await store.load()

        await store.setSaved(false, title: .preview)

        #expect(store.state == .loaded([.fixture]))
        #expect(store.contains(TitleSummary.preview.id))
        #expect(store.mutationFailure == "You're offline.")
    }

    @Test
    func removingATitleThatIsNotSavedSendsNothing() async {
        let watchlist = StubWatchlist(results: [.success([])])
        let store = WatchlistStore(watchlist: watchlist)
        await store.load()

        await store.setSaved(false, title: .preview)

        #expect(await watchlist.changes.isEmpty)
    }

    /// Signing in finishes an add started as a guest, and cannot know whether
    /// the title was already saved elsewhere, so it adds regardless.
    @Test
    func savingATitleThatIsAlreadySavedStillSends() async {
        let watchlist = StubWatchlist(results: [.success([.fixture])])
        let store = WatchlistStore(watchlist: watchlist)
        await store.load()

        await store.setSaved(true, title: .preview)

        #expect(await watchlist.changes == [.added(TitleSummary.preview.id)])
        #expect(store.state.entries?.count == 1, "the title must not be listed twice")
    }

    /// Details answers for one title even when the list was never loaded, so a
    /// bookmark opened from search is right without fetching the whole list.
    @Test
    func reconcileMarksATitleSavedWithoutALoadedList() {
        let store = WatchlistStore(watchlist: StubWatchlist(results: []))

        store.reconcile(titleID: TitleSummary.preview.id, isSaved: true)

        #expect(store.contains(TitleSummary.preview.id))
    }

    @Test
    func reconcileDropsATitleRemovedOnAnotherDevice() async {
        let store = WatchlistStore(watchlist: StubWatchlist(results: [.success([.fixture])]))
        await store.load()

        store.reconcile(titleID: TitleSummary.preview.id, isSaved: false)

        #expect(store.contains(TitleSummary.preview.id) == false)
        #expect(store.state == .loaded([]))
    }

    @Test
    func signingOutClearsAnotherAccountsTitles() async {
        let store = WatchlistStore(watchlist: StubWatchlist(results: [.success([.fixture])]))
        await store.load()

        store.clear()

        #expect(store.state == .loaded([]))
        #expect(store.contains(TitleSummary.preview.id) == false)
    }
}

private actor StubWatchlist: WatchlistManaging {
    enum Change: Equatable {
        case added(String)
        case removed(String)
    }

    private(set) var changes: [Change] = []
    private var results: [Result<[WatchlistEntry], WatchlistFixtureError>]
    private let failingMutations: Bool

    init(
        results: [Result<[WatchlistEntry], WatchlistFixtureError>],
        failingMutations: Bool = false
    ) {
        self.results = results
        self.failingMutations = failingMutations
    }

    func watchlist() async throws -> [WatchlistEntry] {
        try results.removeFirst().get()
    }

    func addToWatchlist(titleID: String) async throws {
        changes.append(.added(titleID))
        try failIfNeeded()
    }

    func removeFromWatchlist(titleID: String) async throws {
        changes.append(.removed(titleID))
        try failIfNeeded()
    }

    private func failIfNeeded() throws {
        if failingMutations {
            throw WatchlistFixtureError.offline
        }
    }
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
