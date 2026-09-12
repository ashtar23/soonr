import Foundation
import Observation

enum TitleDetailsState: Equatable {
    case loading
    case loaded(TitleDetails)
    case notFound
    case failed(message: String)

    var isLoaded: Bool {
        if case .loaded = self {
            return true
        }

        return false
    }
}

@MainActor
@Observable
final class TitleDetailsModel {
    let summary: TitleSummary
    private(set) var state: TitleDetailsState = .loading
    /// Kept beside `state` rather than inside it: the watchlist button toggles
    /// membership on its own, without rebuilding the loaded details.
    private(set) var isInWatchlist = false

    /// Set when a watchlist change was rejected, so the screen can say why the
    /// button sprang back.
    private(set) var watchlistFailure: String?

    @ObservationIgnored private let titleDetails: any TitleDetailsLoading
    @ObservationIgnored private let watchlist: any WatchlistManaging

    init(
        summary: TitleSummary,
        titleDetails: any TitleDetailsLoading,
        watchlist: any WatchlistManaging
    ) {
        self.summary = summary
        self.titleDetails = titleDetails
        self.watchlist = watchlist
    }

    /// Loads details once; repeated calls after a successful load are ignored
    /// so returning to the screen does not refetch.
    func load() async {
        if case .loaded = state {
            return
        }

        await fetch()
    }

    func retry() async {
        await fetch()
    }

    func toggleWatchlist() async {
        await setInWatchlist(isInWatchlist == false)
    }

    /// Moves the button immediately and puts it back if the server refuses,
    /// because waiting on a round trip to fill a bookmark feels broken.
    ///
    /// Adding is safe to call without knowing the current state: the API
    /// treats it as an upsert. That is what makes signing in able to finish an
    /// add the user started as a guest.
    func setInWatchlist(_ shouldSave: Bool) async {
        // A redundant add is allowed, since the API upserts and that is how
        // signing in finishes an add started as a guest. A redundant remove
        // would be a request that changes nothing.
        guard shouldSave || isInWatchlist else {
            return
        }

        let previous = isInWatchlist
        isInWatchlist = shouldSave
        watchlistFailure = nil

        do {
            if shouldSave {
                try await watchlist.addToWatchlist(titleID: summary.id)
            } else {
                try await watchlist.removeFromWatchlist(titleID: summary.id)
            }
        } catch is CancellationError {
            isInWatchlist = previous
        } catch {
            isInWatchlist = previous
            watchlistFailure =
                error.localizedDescription.isEmpty
                ? "That couldn't be saved. Please try again."
                : error.localizedDescription
        }
    }

    func clearWatchlistFailure() {
        watchlistFailure = nil
    }

    private func fetch() async {
        state = .loading

        do {
            let result = try await titleDetails.titleDetails(id: summary.id)
            try Task.checkCancellation()
            isInWatchlist = result?.isInWatchlist ?? false
            state = result.map { .loaded($0.details) } ?? .notFound
        } catch is CancellationError {
            return
        } catch {
            state = .failed(
                message: error.localizedDescription.isEmpty
                    ? "Details couldn't be loaded. Please try again."
                    : error.localizedDescription
            )
        }
    }
}
