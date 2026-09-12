import Foundation

struct SoonrAPI: TitleSearching, TitleDetailsLoading, HomeDiscovering, Sendable {
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

    func titleDetails(id: String) async throws -> TitleDetails? {
        do {
            let response: TitleDetailsResponse = try await client.get(["titles", id])
            return response.details
        } catch APIError.requestFailed(404, _) {
            return nil
        }
    }
}

private struct TitleSearchResponse: Decodable {
    let results: [TitleSummary]
}

private struct TitleDetailsResponse: Decodable {
    let details: TitleDetails
}
