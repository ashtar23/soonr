struct AppDependencies: Sendable {
    let titleSearch: any TitleSearching
    let titleDetails: TitleDetailsDependencies
    let homeDiscovery: any HomeDiscovering
    let watchlist: any WatchlistManaging
    /// One value carrying three capabilities, because the root is the one
    /// place that legitimately knows a single service answers all of them.
    /// Each store still asks for only the part it uses.
    let notifications:
        any NotificationsReading & NotificationPreferencesProviding
            & DeviceRegistering
    /// Pushes invalidations while the app is in front; see NotificationsRealtime.
    let notificationStream: any NotificationStreaming
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
                refreshedAccessToken: { await authentication.refreshedAccessToken() },
                onUnauthorized: { rejected.yield() }
            )
        )

        return AppDependencies(
            titleSearch: api,
            titleDetails: TitleDetailsDependencies(titleDetails: api),
            homeDiscovery: api,
            watchlist: api,
            notifications: api,
            notificationStream: NotificationsSocket(
                configuration: .live,
                accessToken: { await authentication.accessToken() }
            ),
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

    #if DEBUG
        static let preview = AppDependencies(
            titleSearch: PreviewTitleCatalog(),
            titleDetails: .preview,
            homeDiscovery: PreviewTitleCatalog(),
            watchlist: PreviewTitleCatalog(),
            notifications: PreviewNotifications(),
            notificationStream: PreviewNotificationStream(),
            accounts: PreviewTitleCatalog(),
            authentication: PreviewAuthentication(),
            rejectedSessions: AsyncStream { _ in }
        )
    #endif
}
