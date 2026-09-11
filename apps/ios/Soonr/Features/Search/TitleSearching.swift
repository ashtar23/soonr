protocol TitleSearching: Sendable {
    func searchTitles(query: String) async throws -> [TitleSummary]
}
