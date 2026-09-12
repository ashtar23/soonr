/// Live capabilities created once by the app and passed into feature roots.
struct AppDependencies: Sendable {
    let titleSearch: any TitleSearching
    let titleDetails: any TitleDetailsLoading
    let homeDiscovery: any HomeDiscovering

    static func live() -> AppDependencies {
        let api = SoonrAPI(configuration: .live)
        return AppDependencies(titleSearch: api, titleDetails: api, homeDiscovery: api)
    }

    static let preview = AppDependencies(
        titleSearch: PreviewTitleCatalog(),
        titleDetails: PreviewTitleCatalog(),
        homeDiscovery: PreviewTitleCatalog()
    )
}
