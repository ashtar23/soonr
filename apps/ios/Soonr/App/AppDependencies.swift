/// Live capabilities created once by the app and passed into feature roots.
struct AppDependencies: Sendable {
    let titleSearch: any TitleSearching
    let titleDetails: TitleDetailsDependencies
    let homeDiscovery: any HomeDiscovering
    let watchlist: any WatchlistManaging
    let notifications: any NotificationsProviding
    let accounts: any AccountCreating
    /// Shared with the session store, so requests and the signed-in state read
    /// the same session.
    let authentication: any Authenticating
    /// Yields when the server rejects the session, so the app root can end it.
    let rejectedSessions: AsyncStream<Void>

    static func live() -> AppDependencies {
        let authentication = liveAuthentication()
        let (rejectedSessions, rejected) = AsyncStream<Void>.makeStream()
        let api = SoonrAPI(
            client: APIClient(
                configuration: .live,
                accessToken: { await authentication.accessToken() },
                onUnauthorized: { rejected.yield() }
            )
        )

        return AppDependencies(
            titleSearch: api,
            titleDetails: TitleDetailsDependencies(titleDetails: api),
            homeDiscovery: api,
            watchlist: api,
            notifications: api,
            accounts: api,
            authentication: authentication,
            rejectedSessions: rejectedSessions
        )
    }

    /// A build without Supabase settings, which is the case on a fresh clone
    /// and in CI, browses as a guest.
    private static func liveAuthentication() -> any Authenticating {
        guard let supabase = AppConfiguration.live.supabase else {
            return UnconfiguredAuthentication()
        }

        return SupabaseAuthService(configuration: supabase)
    }

    static let preview = AppDependencies(
        titleSearch: PreviewTitleCatalog(),
        titleDetails: .preview,
        homeDiscovery: PreviewTitleCatalog(),
        watchlist: PreviewTitleCatalog(),
        notifications: PreviewNotifications(),
        accounts: PreviewTitleCatalog(),
        authentication: PreviewAuthentication(),
        rejectedSessions: AsyncStream { _ in }
    )
}
