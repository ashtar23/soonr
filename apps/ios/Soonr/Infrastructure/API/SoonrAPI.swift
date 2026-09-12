import Foundation

struct SoonrAPI: TitleSearching, TitleDetailsLoading, HomeDiscovering, WatchlistManaging, Sendable {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    init(configuration: AppConfiguration) {
        self.init(client: APIClient(configuration: configuration))
    }

    func searchTitles(query: String) async throws -> [TitleSummary] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedQuery.count >= 2 else {
            return []
        }

        let response: TitleSearchResponse = try await client.get(
            ["titles"],
            queryItems: [
                URLQueryItem(name: "query", value: normalizedQuery),
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "limit", value: "20"),
            ]
        )
        return response.results
    }

    func homeDiscovery() async throws -> HomeDiscovery {
        try await client.get(["home", "discovery"])
    }

    func titleDetails(id: String) async throws -> TitleDetailsResult? {
        do {
            return try await client.get(["titles", id])
        } catch APIError.requestFailed(404, _) {
            return nil
        }
    }

    func addToWatchlist(titleID: String) async throws {
        try await client.post(["watchlist"], body: WatchlistMutationBody(titleID: titleID))
    }

    func removeFromWatchlist(titleID: String) async throws {
        try await client.delete(["watchlist", titleID])
    }
}

/// The title travels in the body on add, and in the path on remove, which is
/// how `apps/api` defines the two routes.
private struct WatchlistMutationBody: Encodable {
    let titleID: String

    enum CodingKeys: String, CodingKey {
        case titleID = "titleId"
    }
}

private struct TitleSearchResponse: Decodable {
    let results: [TitleSummary]
}
