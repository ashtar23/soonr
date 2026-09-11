/// Live capabilities created once by the app and passed into feature roots.
struct AppDependencies: Sendable {
    let titleSearch: any TitleSearching

    static func live() -> AppDependencies {
        AppDependencies(titleSearch: SoonrAPI(configuration: .live))
    }

    static let preview = AppDependencies(titleSearch: PreviewTitleCatalog())
}
