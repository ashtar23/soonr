/// Search, Home and the watchlist all push details without using this
/// themselves, so bundling keeps them from threading a capability each time
/// the screen grows one. Membership is not here: it lives in the shared
/// `WatchlistStore`.
struct TitleDetailsDependencies: Sendable {
    let titleDetails: any TitleDetailsLoading
}
