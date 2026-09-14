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
        #expect(store.state == .failed(.unknown(message: "You're offline.")))

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
        #expect(store.mutationFailure == .unknown(message: "You're offline."))
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
        #expect(store.mutationFailure == .unknown(message: "You're offline."))
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
    // MARK: - Paging

    @Test
    func theSecondPageIsAppendedBelowTheFirst() async {
        let second = WatchlistEntry.fixture(id: "watchlist-2", titleID: "rawg:2")
        let watchlist = StubWatchlist(
            results: [.success([.fixture])],
            firstPageCursor: "cursor-2",
            laterPages: [Page(items: [second], nextCursor: nil)]
        )
        let store = WatchlistStore(watchlist: watchlist)
        await store.load()
        #expect(store.hasMore)

        await store.loadMore()

        #expect(store.state.entries?.map(\.id) == ["watchlist-1", "watchlist-2"])
        #expect(await watchlist.cursorsAsked == [nil, "cursor-2"])
    }

    /// Membership answers the bookmark on every screen, so it has to grow with
    /// what has been loaded.
    @Test
    func alaterPageIsAlsoKnownToBeSaved() async {
        let second = WatchlistEntry.fixture(id: "watchlist-2", titleID: "rawg:2")
        let watchlist = StubWatchlist(
            results: [.success([.fixture])],
            firstPageCursor: "cursor-2",
            laterPages: [Page(items: [second], nextCursor: nil)]
        )
        let store = WatchlistStore(watchlist: watchlist)
        await store.load()
        #expect(store.contains("rawg:2") == false)

        await store.loadMore()

        #expect(store.contains("rawg:2"))
    }

    @Test
    func afastScrollAsksForThePageOnce() async {
        let watchlist = StubWatchlist(
            results: [.success([.fixture])],
            firstPageCursor: "cursor-2",
            laterPages: [Page(items: [], nextCursor: "cursor-3")]
        )
        let store = WatchlistStore(watchlist: watchlist)
        await store.load()

        async let first: Void = store.loadMore()
        async let second: Void = store.loadMore()
        _ = await (first, second)

        #expect(await watchlist.cursorsAsked == [nil, "cursor-2"])
    }

    /// Saving puts the title on top straight away; the page it really belongs
    /// to must not then show it a second time.
    @Test
    func atitleSavedWhilePagingIsNotShownTwiceWhenItsPageArrives() async {
        let saved = WatchlistEntry.fixture(id: "watchlist-9", titleID: TitleSummary.preview.id)
        let watchlist = StubWatchlist(
            results: [.success([])],
            firstPageCursor: "cursor-2",
            laterPages: [Page(items: [saved], nextCursor: nil)]
        )
        let store = WatchlistStore(watchlist: watchlist)
        await store.load()

        await store.setSaved(true, title: .preview)
        await store.loadMore()

        #expect(store.state.entries?.count == 1)
    }

    /// Removing has to forget the title as well as drop the row, or saving it
    /// again would be refused as a duplicate and never come back.
    @Test
    func atitleRemovedAndSavedAgainComesBack() async {
        let watchlist = StubWatchlist(results: [.success([.fixture])])
        let store = WatchlistStore(watchlist: watchlist)
        await store.load()

        await store.setSaved(false, title: .preview)
        #expect(store.state.entries?.isEmpty == true)
        await store.setSaved(true, title: .preview)

        #expect(store.state.entries?.count == 1)
        #expect(store.contains(TitleSummary.preview.id))
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
    private let firstPageCursor: String?
    private var laterPages: [Page<WatchlistEntry>]
    private(set) var cursorsAsked: [String?] = []

    init(
        results: [Result<[WatchlistEntry], WatchlistFixtureError>],
        failingMutations: Bool = false,
        firstPageCursor: String? = nil,
        laterPages: [Page<WatchlistEntry>] = []
    ) {
        self.results = results
        self.failingMutations = failingMutations
        self.firstPageCursor = firstPageCursor
        self.laterPages = laterPages
    }

    func watchlist(after cursor: String?) async throws -> Page<WatchlistEntry> {
        cursorsAsked.append(cursor)

        if cursor != nil, laterPages.isEmpty == false {
            return laterPages.removeFirst()
        }

        return Page(items: try results.removeFirst().get(), nextCursor: firstPageCursor)
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

private extension TitleSummary {
    /// The preview title under another id, so a test can hold two.
    static func preview(id: String) -> TitleSummary {
        let preview = TitleSummary.preview
        return TitleSummary(
            id: id,
            kind: preview.kind,
            source: preview.source,
            externalID: preview.externalID,
            slug: preview.slug,
            name: preview.name,
            coverImageURL: preview.coverImageURL,
            earliestReleaseDate: preview.earliestReleaseDate,
            platforms: preview.platforms,
            rawgRating: preview.rawgRating,
            rawgRatingsCount: preview.rawgRatingsCount,
            rawgMetacritic: preview.rawgMetacritic,
            rawgAdded: preview.rawgAdded,
            rawgReviewsCount: preview.rawgReviewsCount,
            rawgSuggestionsCount: preview.rawgSuggestionsCount,
            rawgRatingTop: preview.rawgRatingTop
        )
    }
}

private extension WatchlistEntry {
    /// A second entry, for tests about order, identity and paging.
    static func fixture(id: String, titleID: String) -> WatchlistEntry {
        WatchlistEntry(
            id: id,
            title: .preview(id: titleID),
            addedAt: "2026-01-01T09:00:00Z"
        )
    }

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
