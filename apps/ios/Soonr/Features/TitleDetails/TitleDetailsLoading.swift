protocol TitleDetailsLoading: Sendable {
    /// Returns `nil` when the title does not exist.
    func titleDetails(id: String) async throws -> TitleDetails?
}
