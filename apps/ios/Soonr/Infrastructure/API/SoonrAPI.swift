import Foundation

struct SoonrAPI:
    TitleSearching, TitleDetailsLoading, HomeDiscovering, WatchlistManaging, AccountCreating,
    Sendable
{
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

    func watchlist() async throws -> [WatchlistEntry] {
        let response: WatchlistResponse = try await client.get(["watchlist"])
        return response.items
    }

    func addToWatchlist(titleID: String) async throws {
        try await client.post(["watchlist"], body: WatchlistMutationBody(titleID: titleID))
    }

    func removeFromWatchlist(titleID: String) async throws {
        try await client.delete(["watchlist", titleID])
    }

    func emailAvailability(email: String) async throws -> FieldAvailability {
        try await client.get(
            ["auth", "email-availability"],
            queryItems: [URLQueryItem(name: "email", value: email)]
        )
    }

    func usernameAvailability(username: String) async throws -> FieldAvailability {
        try await client.get(
            ["profile", "username-availability"],
            queryItems: [URLQueryItem(name: "username", value: username)]
        )
    }

    func signUp(email: String, password: String, username: String) async throws {
        do {
            try await client.post(
                ["auth", "sign-up"],
                body: SignUpBody(email: email, password: password, username: username)
            )
        } catch APIError.requestFailed(409, let message) {
            throw SignUpFailure.conflict(message)
        } catch APIError.requestFailed(400, let message) {
            throw SignUpFailure.invalid(message)
        }
    }
}

private struct SignUpBody: Encodable {
    let email: String
    let password: String
    let username: String
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

/// `nextCursor` is ignored while the screen shows a single page.
private struct WatchlistResponse: Decodable {
    let items: [WatchlistEntry]
}
