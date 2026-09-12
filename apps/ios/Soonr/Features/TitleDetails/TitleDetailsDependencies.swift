/// What the details screen needs, carried as one value.
///
/// Search, Home, and the watchlist all push details without using these
/// themselves, so bundling keeps them from threading a capability each time
/// the screen grows one.
struct TitleDetailsDependencies: Sendable {
    let titleDetails: any TitleDetailsLoading
    let watchlist: any WatchlistManaging
}
