import Foundation
import Observation

enum WatchlistState: Equatable {
    case loading
    case loaded([WatchlistEntry])
    case failed(message: String)

    var entries: [WatchlistEntry]? {
        if case let .loaded(entries) = self {
            return entries
        }

        return nil
    }
}

@MainActor
@Observable
final class WatchlistModel {
    private(set) var state: WatchlistState = .loading

    @ObservationIgnored private let watchlist: any WatchlistManaging

    init(watchlist: any WatchlistManaging) {
        self.watchlist = watchlist
    }

    /// Reloads every time the tab appears, because titles are saved from the
    /// details screen rather than here. A list already on screen stays there
    /// while it reloads, so coming back does not flash a spinner.
    func load() async {
        await fetch(showingLoadingState: state.entries == nil)
    }

    func retry() async {
        await fetch(showingLoadingState: true)
    }

    func refresh() async {
        await fetch(showingLoadingState: false)
    }

    /// Signing out clears the list rather than leaving another account's
    /// titles on screen until the next load.
    func clear() {
        state = .loaded([])
    }

    private func fetch(showingLoadingState: Bool) async {
        if showingLoadingState {
            state = .loading
        }

        do {
            let entries = try await watchlist.watchlist()
            try Task.checkCancellation()
            state = .loaded(entries)
        } catch is CancellationError {
            return
        } catch {
            state = .failed(
                message: error.localizedDescription.isEmpty
                    ? "Your watchlist couldn't be loaded. Please try again."
                    : error.localizedDescription
            )
        }
    }
}
