/// Live capabilities created once by the app and passed into feature roots.
struct AppDependencies: Sendable {
    let titleSearch: any TitleSearching
    let titleDetails: any TitleDetailsLoading
    let homeDiscovery: any HomeDiscovering
    /// Shared with the session store, so requests and the signed-in state read
    /// the same session.
    let authentication: any Authenticating

    static func live() -> AppDependencies {
        let authentication = liveAuthentication()
        let api = SoonrAPI(
            client: APIClient(
                configuration: .live,
                accessToken: { await authentication.accessToken() }
            )
        )

        return AppDependencies(
            titleSearch: api,
            titleDetails: api,
            homeDiscovery: api,
            authentication: authentication
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
        titleDetails: PreviewTitleCatalog(),
        homeDiscovery: PreviewTitleCatalog(),
        authentication: PreviewAuthentication()
    )
}
