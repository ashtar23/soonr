/// What the details screen needs, carried as one value.
///
/// Search, Home, and the watchlist all push details without using this
/// themselves, so bundling keeps them from threading a capability each time the
/// screen grows one. Watchlist membership is not here: it lives in the shared
/// `WatchlistStore`, which the screen reads from the environment.
struct TitleDetailsDependencies: Sendable {
    let titleDetails: any TitleDetailsLoading
}
