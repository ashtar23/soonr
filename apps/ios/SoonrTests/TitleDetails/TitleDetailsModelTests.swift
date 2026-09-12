import Foundation
import Testing

@testable import Soonr

@MainActor
@Suite(.tags(.networking))
struct TitleDetailsModelTests {
    @Test
    func successfulLoadShowsDetailsForTheSelectedTitle() async {
        let loader = RecordingTitleDetails(results: [.success(.preview)])
        let model = TitleDetailsModel(
            summary: .preview, titleDetails: loader, watchlist: RecordingWatchlist())

        await model.load()

        #expect(model.state == .loaded(.preview))
        #expect(await loader.requestedIDs == [TitleSummary.preview.id])
    }

    @Test
    func missingTitleShowsNotFound() async {
        let model = TitleDetailsModel(
            summary: .preview,
            titleDetails: RecordingTitleDetails(results: [.success(nil)]),
            watchlist: RecordingWatchlist()
        )

        await model.load()

        #expect(model.state == .notFound)
    }

    @Test
    func failureShowsItsMessageAndRetryRecovers() async {
        let loader = RecordingTitleDetails(results: [
            .failure(DetailsFixtureError.offline),
            .success(.preview),
        ])
        let model = TitleDetailsModel(
            summary: .preview, titleDetails: loader, watchlist: RecordingWatchlist())

        await model.load()
        #expect(model.state == .failed(message: "You're offline."))

        await model.retry()
        #expect(model.state == .loaded(.preview))
        #expect(await loader.requestedIDs.count == 2)
    }

    @Test
    func loadRecordsWatchlistMembership() async {
        let model = TitleDetailsModel(
            summary: .preview,
            titleDetails: RecordingTitleDetails(results: [.success(.saved)]),
            watchlist: RecordingWatchlist()
        )

        await model.load()

        #expect(model.state == .loaded(.preview))
        #expect(model.isInWatchlist)
    }

    @Test
    func aTitleThatIsNotSavedLoadsAsNotInTheWatchlist() async {
        let model = TitleDetailsModel(
            summary: .preview,
            titleDetails: RecordingTitleDetails(results: [.success(.preview)]),
            watchlist: RecordingWatchlist()
        )

        await model.load()

        #expect(model.isInWatchlist == false)
    }

    @Test
    func savingATitleSendsItAndFillsTheButton() async {
        let watchlist = RecordingWatchlist()
        let model = TitleDetailsModel(
            summary: .preview,
            titleDetails: RecordingTitleDetails(results: [.success(.preview)]),
            watchlist: watchlist
        )
        await model.load()

        await model.toggleWatchlist()

        #expect(model.isInWatchlist)
        #expect(model.watchlistFailure == nil)
        #expect(await watchlist.changes == [.added(TitleSummary.preview.id)])
    }

    @Test
    func removingATitleSendsTheRemoval() async {
        let watchlist = RecordingWatchlist()
        let model = TitleDetailsModel(
            summary: .preview,
            titleDetails: RecordingTitleDetails(results: [.success(.saved)]),
            watchlist: watchlist
        )
        await model.load()

        await model.toggleWatchlist()

        #expect(model.isInWatchlist == false)
        #expect(await watchlist.changes == [.removed(TitleSummary.preview.id)])
    }

    /// The button moves first, so a rejected change has to put it back rather
    /// than leave the screen claiming something that was never saved.
    @Test
    func aRejectedSaveRollsTheButtonBackAndReportsWhy() async {
        let model = TitleDetailsModel(
            summary: .preview,
            titleDetails: RecordingTitleDetails(results: [.success(.preview)]),
            watchlist: RecordingWatchlist(failing: .offline)
        )
        await model.load()

        await model.toggleWatchlist()

        #expect(model.isInWatchlist == false)
        #expect(model.watchlistFailure == "You're offline.")
    }

    @Test
    func aRejectedRemovalRestoresTheSavedState() async {
        let model = TitleDetailsModel(
            summary: .preview,
            titleDetails: RecordingTitleDetails(results: [.success(.saved)]),
            watchlist: RecordingWatchlist(failing: .offline)
        )
        await model.load()

        await model.toggleWatchlist()

        #expect(model.isInWatchlist)
        #expect(model.watchlistFailure == "You're offline.")
    }

    /// Signing in finishes an add a guest started, and it cannot know whether
    /// the title was already saved on another device, so it adds regardless.
    @Test
    func savingAfterSignInAddsEvenWhenAlreadyMarkedSaved() async {
        let watchlist = RecordingWatchlist()
        let model = TitleDetailsModel(
            summary: .preview,
            titleDetails: RecordingTitleDetails(results: [.success(.saved)]),
            watchlist: watchlist
        )
        await model.load()

        await model.setInWatchlist(true)

        #expect(model.isInWatchlist)
        #expect(await watchlist.changes == [.added(TitleSummary.preview.id)])
    }

    @Test
    func removingATitleThatIsNotSavedSendsNothing() async {
        let watchlist = RecordingWatchlist()
        let model = TitleDetailsModel(
            summary: .preview,
            titleDetails: RecordingTitleDetails(results: [.success(.preview)]),
            watchlist: watchlist
        )
        await model.load()

        await model.setInWatchlist(false)

        #expect(await watchlist.changes.isEmpty)
    }

    @Test
    func loadingAgainAfterSuccessDoesNotRefetch() async {
        let loader = RecordingTitleDetails(results: [.success(.preview)])
        let model = TitleDetailsModel(
            summary: .preview, titleDetails: loader, watchlist: RecordingWatchlist())

        await model.load()
        await model.load()

        #expect(model.state == .loaded(.preview))
        #expect(await loader.requestedIDs.count == 1)
    }
}

private actor RecordingWatchlist: WatchlistManaging {
    enum Change: Equatable {
        case added(String)
        case removed(String)
    }

    private(set) var changes: [Change] = []
    private let failure: DetailsFixtureError?

    init(failing failure: DetailsFixtureError? = nil) {
        self.failure = failure
    }

    func watchlist() async throws -> [WatchlistEntry] {
        []
    }

    func addToWatchlist(titleID: String) async throws {
        changes.append(.added(titleID))
        if let failure {
            throw failure
        }
    }

    func removeFromWatchlist(titleID: String) async throws {
        changes.append(.removed(titleID))
        if let failure {
            throw failure
        }
    }
}

private actor RecordingTitleDetails: TitleDetailsLoading {
    private(set) var requestedIDs: [String] = []
    private var results: [Result<TitleDetailsResult?, DetailsFixtureError>]

    init(results: [Result<TitleDetailsResult?, DetailsFixtureError>]) {
        self.results = results
    }

    func titleDetails(id: String) async throws -> TitleDetailsResult? {
        requestedIDs.append(id)
        return try results.removeFirst().get()
    }
}

private extension TitleDetailsResult {
    static let preview = TitleDetailsResult(details: .preview, isInWatchlist: false)
    static let saved = TitleDetailsResult(details: .preview, isInWatchlist: true)
}

private enum DetailsFixtureError: Error, LocalizedError, Sendable {
    case offline

    var errorDescription: String? {
        "You're offline."
    }
}
