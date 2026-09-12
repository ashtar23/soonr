protocol WatchlistManaging: Sendable {
    /// The first page, newest first. Paging is deferred with Home's `See all`.
    func watchlist() async throws -> [WatchlistEntry]

    /// Adding a title that is already saved succeeds without changing when it
    /// was added, so a caller that cannot know the current state may add
    /// freely.
    func addToWatchlist(titleID: String) async throws
    func removeFromWatchlist(titleID: String) async throws
}
