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

    /// True while a further page is on its way, so a fast scroll cannot start
    /// the same request several times over.
    private(set) var isLoadingMore = false

    var hasMore: Bool {
        state.entries != nil && page.hasMore
    }

    @ObservationIgnored private let watchlist: any WatchlistManaging
    @ObservationIgnored private var page = PagedList<WatchlistEntry>()

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
        page = PagedList<WatchlistEntry>()
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

    /// The next page, asked for when the last row comes into view. Silent
    /// about failure: the rows already on screen are still good, and reaching
    /// the bottom again retries.
    func loadMore() async {
        guard isLoadingMore == false, let cursor = page.nextCursor else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let next = try await watchlist.watchlist(after: cursor)
            try Task.checkCancellation()
            // A title saved while its real entry sat on a page not yet loaded
            // is held under a stand-in id, which the paged list cannot match
            // against the server's own. Letting the server's copy win keeps the
            // title once rather than twice.
            let arriving = Set(next.items.map(\.title.id))
            page.removeAll { arriving.contains($0.title.id) }
            page.append(next)
            state = .loaded(page.items)
            // Membership grows with what has been seen; a title on a page not
            // loaded yet is still answered by title details, which reports it
            // for one title authoritatively.
            savedIDs.formUnion(next.items.map(\.title.id))
        } catch is CancellationError {
            return
        } catch {
            AppLog.watchlist.error("Could not load more of the watchlist: \(error)")
        }
    }

    private func insertEntry(for title: TitleSummary) {
        // Identity here is the entry, but a title is saved once however many
        // entries could hold it — and the entry this makes carries a stand-in
        // id, so the paged list cannot tell the two apart on its own.
        guard let entries = state.entries,
            entries.contains(where: { $0.title.id == title.id }) == false
        else {
            return
        }

        // Newest first, matching the server's default order. The identifier
        // and timestamp are replaced by the server's own on the next load.
        page.prepend(
            WatchlistEntry(
                id: title.id,
                title: title,
                addedAt: ISO8601DateFormatter().string(from: .now)
            )
        )
        state = .loaded(page.items)
    }

    private func removeEntry(titleID: String) {
        guard state.entries != nil else {
            return
        }

        page.removeAll { $0.title.id == titleID }
        state = .loaded(page.items)
    }

    private func fetch(showingLoadingState: Bool) async {
        if showingLoadingState {
            state = .loading
        }

        do {
            let first = try await watchlist.watchlist(after: nil)
            try Task.checkCancellation()
            page.reset(to: first)
            state = .loaded(page.items)
            savedIDs = Set(page.items.map(\.title.id))
        } catch is CancellationError {
            return
        } catch {
            AppLog.watchlist.error("Could not load the watchlist: \(error)")
            state = .failed(FailureReason(error))
        }
    }
}
