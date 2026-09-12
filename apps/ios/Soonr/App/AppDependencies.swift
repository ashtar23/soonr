/// Live capabilities created once by the app and passed into feature roots.
struct AppDependencies: Sendable {
    let titleSearch: any TitleSearching
    let titleDetails: any TitleDetailsLoading
    let homeDiscovery: any HomeDiscovering

    static func live() -> AppDependencies {
        let api = SoonrAPI(configuration: .live)
        return AppDependencies(titleSearch: api, titleDetails: api, homeDiscovery: api)
    }

    /// Authentication is created separately from the API capabilities because
    /// the app root owns the session, and a build without Supabase settings
    /// still runs as a guest.
    static func liveAuthentication() -> any Authenticating {
        guard let supabase = AppConfiguration.live.supabase else {
            return UnconfiguredAuthentication()
        }

        return SupabaseAuthService(configuration: supabase)
    }

    static let preview = AppDependencies(
        titleSearch: PreviewTitleCatalog(),
        titleDetails: PreviewTitleCatalog(),
        homeDiscovery: PreviewTitleCatalog()
    )
}
