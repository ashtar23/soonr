protocol HomeDiscovering: Sendable {
    func homeDiscovery() async throws -> HomeDiscovery
}
