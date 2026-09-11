/// Live capabilities created once by the app and passed into feature roots.
struct AppDependencies: Sendable {
    let titleSearch: any TitleSearching
    let titleDetails: any TitleDetailsLoading

    static func live() -> AppDependencies {
        let api = SoonrAPI(configuration: .live)
        return AppDependencies(titleSearch: api, titleDetails: api)
    }

    static let preview = AppDependencies(
        titleSearch: PreviewTitleCatalog(),
        titleDetails: PreviewTitleCatalog()
    )
}
