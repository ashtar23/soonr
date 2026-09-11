import Foundation

struct SoonrAPI: TitleSearching, Sendable {
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
}

private struct TitleSearchResponse: Decodable {
    let results: [TitleSummary]
}
