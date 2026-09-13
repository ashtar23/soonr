import Foundation
import Observation

enum WatchlistState: Equatable {
    case loading
    case loaded([WatchlistEntry])
    case failed(FailureReason)

    var entries: [WatchlistEntry]? {
        if case let .loaded(entries) = self {
            return entries
        }

        return nil
    }
}

/// One store for saved titles, because screens each keeping a copy meant
/// unsaving a title left it on the tab until a refresh, and opening one from
/// the tab showed an empty bookmark until its own request answered a question
/// the tab had already answered.
@MainActor
@Observable
final class WatchlistStore {
    private(set) var state: WatchlistState = .loading
    /// Kept beside `state` so membership stays answerable while the list is
    /// loading or failed.
    private(set) var savedIDs: Set<String> = []
    /// Set when a save or removal was rejected, so the screen that asked can
    /// say why the bookmark sprang back.
    private(set) var mutationFailure: FailureReason?

    @ObservationIgnored private let watchlist: any WatchlistManaging

    init(watchlist: any WatchlistManaging) {
        self.watchlist = watchlist
    }

    func contains(_ titleID: String) -> Bool {
        savedIDs.contains(titleID)
    }

    /// Loaded once when the session becomes signed in, so a bookmark is
    /// already known by the time any title is opened.
    func load() async {
        await fetch(showingLoadingState: state.entries == nil)
    }

    func retry() async {
        await fetch(showingLoadingState: true)
    }

    func refresh() async {
        await fetch(showingLoadingState: false)
    }

    /// Drops another account's titles rather than leaving them on screen.
    func clear() {
        state = .loaded([])
        savedIDs = []
        mutationFailure = nil
    }

    /// Title details report membership for one title, which is authoritative
    /// for that title even when the list is stale or was never loaded.
    func reconcile(titleID: String, isSaved: Bool) {
        guard contains(titleID) != isSaved else {
            return
        }

        if isSaved {
            savedIDs.insert(titleID)
        } else {
            savedIDs.remove(titleID)
            removeEntry(titleID: titleID)
        }
    }

    /// Moves the bookmark and the list first, putting both back if the server
    /// refuses. Adding without knowing the current state is safe: the API
    /// upserts, which is how signing in finishes an add started as a guest.
    func setSaved(_ shouldSave: Bool, title: TitleSummary) async {
        guard shouldSave || contains(title.id) else {
            return
        }

        let previousIDs = savedIDs
        let previousState = state
        mutationFailure = nil

        if shouldSave {
            savedIDs.insert(title.id)
            insertEntry(for: title)
        } else {
            savedIDs.remove(title.id)
            removeEntry(titleID: title.id)
        }

        do {
            if shouldSave {
                try await watchlist.addToWatchlist(titleID: title.id)
            } else {
                try await watchlist.removeFromWatchlist(titleID: title.id)
            }
        } catch is CancellationError {
            savedIDs = previousIDs
            state = previousState
        } catch {
            AppLog.watchlist.error(
                "Could not \(shouldSave ? "save" : "remove", privacy: .public) a title: \(error)"
            )
            savedIDs = previousIDs
            state = previousState
            mutationFailure = FailureReason(error)
        }
    }

    func clearMutationFailure() {
        mutationFailure = nil
    }

    private func insertEntry(for title: TitleSummary) {
        guard let entries = state.entries,
            entries.contains(where: { $0.title.id == title.id }) == false
        else {
            return
        }

        // Newest first, matching the server's default order. The identifier
        // and timestamp are replaced by the server's own on the next load.
        let entry = WatchlistEntry(
            id: title.id,
            title: title,
            addedAt: ISO8601DateFormatter().string(from: .now)
        )
        state = .loaded([entry] + entries)
    }

    private func removeEntry(titleID: String) {
        guard let entries = state.entries else {
            return
        }

        state = .loaded(entries.filter { $0.title.id != titleID })
    }

    private func fetch(showingLoadingState: Bool) async {
        if showingLoadingState {
            state = .loading
        }

        do {
            let entries = try await watchlist.watchlist(after: nil).items
            try Task.checkCancellation()
            state = .loaded(entries)
            savedIDs = Set(entries.map(\.title.id))
        } catch is CancellationError {
            return
        } catch {
            AppLog.watchlist.error("Could not load the watchlist: \(error)")
            state = .failed(FailureReason(error))
        }
    }
}
