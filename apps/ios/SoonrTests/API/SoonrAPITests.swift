import Foundation
import Testing

@testable import Soonr

@Suite(.tags(.networking))
struct SoonrAPITests {
    @Test
    func searchSendsTheTrimmedQueryWithSharedHeaders() async throws {
        let transport = StubTransport(.init(statusCode: 200, body: Self.searchJSON))
        let api = transport.api()

        _ = try await api.searchTitles(query: "  hades  ")

        let request = try #require(await transport.requests.first)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "api.soonr.test")
        #expect(components.path == "/titles")
        #expect(
            components.queryItems == [
                URLQueryItem(name: "query", value: "hades"),
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "limit", value: "20"),
            ]
        )
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "apikey") == "test-publishable-key")
        #expect(request.timeoutInterval == 8)
    }

    @Test
    func searchDecodesResults() async throws {
        let api = StubTransport(.init(statusCode: 200, body: Self.searchJSON)).api()

        let results = try await api.searchTitles(query: "hades")

        #expect(results.map(\.id) == ["rawg:274755"])
        #expect(results.first?.name == "Hades")
    }

    @Test
    func shortQueryDoesNotSendARequest() async throws {
        let transport = StubTransport(.init(statusCode: 200, body: Self.searchJSON))

        let results = try await transport.api().searchTitles(query: " h ")

        #expect(results.isEmpty)
        #expect(await transport.requests.isEmpty)
    }

    @Test
    func pathComponentsArePercentEncoded() throws {
        let client = APIClient(
            configuration: .test,
            transport: { _ in
                Issue.record("Building a request must not send it.")
                throw URLError(.badURL)
            }
        )

        let request = try client.makeRequest(pathComponents: ["titles", "rawg/1 2"])

        let path = try #require(request.url?.path(percentEncoded: true))
        #expect(path.hasPrefix("/titles/"))
        #expect(path.contains("%2F"))
        #expect(request.url?.path(percentEncoded: false) == "/titles/rawg/1 2")
    }

    @Test
    func serverFailureSurfacesTheAPIMessage() async {
        let api = StubTransport(
            .init(statusCode: 500, body: #"{"error":"Database unavailable."}"#)
        ).api()

        await #expect(
            throws: APIError.requestFailed(statusCode: 500, message: "Database unavailable.")
        ) {
            try await api.searchTitles(query: "hades")
        }
    }

    @Test
    func malformedPayloadThrowsInvalidPayload() async {
        let api = StubTransport(.init(statusCode: 200, body: #"{"results":[{"id":1}]}"#)).api()

        await #expect(throws: APIError.invalidPayload) {
            try await api.searchTitles(query: "hades")
        }
    }

    @Test
    func titleDetailsRequestTargetsTheTitleResource() async throws {
        let transport = StubTransport(.init(statusCode: 200, body: Self.fullDetailsJSON))

        _ = try await transport.api().titleDetails(id: "rawg:891238")

        let request = try #require(await transport.requests.first)
        #expect(request.url?.path(percentEncoded: false) == "/titles/rawg:891238")
    }

    @Test
    func fullTitleDetailsDecode() async throws {
        let api = StubTransport(.init(statusCode: 200, body: Self.fullDetailsJSON)).api()

        let details = try #require(try await api.titleDetails(id: "rawg:891238"))

        #expect(details.summary.id == "rawg:891238")
        #expect(details.summary.name == "Hades II")
        #expect(details.summary.platforms.map(\.name) == ["PC", "Nintendo Switch"])
        #expect(details.displayDescription == "The first-ever sequel from Supergiant Games.")
        #expect(details.genres == ["Action", "RPG"])
        #expect(details.developers == ["Supergiant Games"])
        #expect(details.publishers == ["Supergiant Games"])
        #expect(
            details.releases == [
                TitleRelease(
                    platformID: "rawg-platform:4",
                    platformName: "PC",
                    releaseDate: "2025-09-25",
                    precision: .day
                ),
                TitleRelease(
                    platformID: "rawg-platform:7",
                    platformName: "Nintendo Switch",
                    releaseDate: nil,
                    precision: .unknown
                ),
            ]
        )
    }

    @Test
    func sparseTitleDetailsDecode() async throws {
        let api = StubTransport(.init(statusCode: 200, body: Self.sparseDetailsJSON)).api()

        let details = try #require(try await api.titleDetails(id: "rawg:274755"))

        #expect(details.summary.name == "Hades")
        #expect(details.summary.coverImageURL == nil)
        #expect(details.displayDescription == nil)
        #expect(details.genres.isEmpty)
        #expect(details.developers.isEmpty)
        #expect(details.publishers.isEmpty)
        #expect(details.releases.isEmpty)
    }

    @Test
    func unrecognizedReleasePrecisionDecodesAsUnknown() async throws {
        let body = Self.fullDetailsJSON.replacingOccurrences(of: "\"day\"", with: "\"quarter\"")
        let api = StubTransport(.init(statusCode: 200, body: body)).api()

        let details = try #require(try await api.titleDetails(id: "rawg:891238"))

        #expect(details.releases.map(\.precision) == [.unknown, .unknown])
    }

    @Test
    func missingTitleReturnsNil() async throws {
        let api = StubTransport(
            .init(statusCode: 404, body: #"{"error":"Title not found."}"#)
        ).api()

        #expect(try await api.titleDetails(id: "rawg:0") == nil)
    }

    @Test
    func homeDiscoveryRequestTargetsTheDiscoveryResource() async throws {
        let transport = StubTransport(.init(statusCode: 200, body: Self.homeDiscoveryJSON))

        _ = try await transport.api().homeDiscovery()

        let request = try #require(await transport.requests.first)
        #expect(request.url?.path(percentEncoded: false) == "/home/discovery")
    }

    @Test
    func homeDiscoveryDecodesEveryRail() async throws {
        let api = StubTransport(.init(statusCode: 200, body: Self.homeDiscoveryJSON)).api()

        let discovery = try await api.homeDiscovery()

        #expect(discovery.upcoming.map(\.name) == ["Marvel's Wolverine"])
        #expect(discovery.latest.map(\.name) == ["Hades"])
        #expect(discovery.popular.isEmpty)
        #expect(discovery.populatedRails.map(\.section) == [.upcoming, .latest])
    }

    @Test
    func aSignedInRequestCarriesTheSession() async throws {
        let transport = StubTransport(.init(statusCode: 200, body: Self.searchJSON))

        _ = try await transport.api(accessToken: "session-token").searchTitles(query: "hades")

        let request = try #require(await transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer session-token")
    }

    @Test
    func aGuestRequestCarriesNoAuthorizationHeader() async throws {
        let transport = StubTransport(.init(statusCode: 200, body: Self.searchJSON))

        _ = try await transport.api().searchTitles(query: "hades")

        let request = try #require(await transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test
    func aRejectedSessionIsReportedAsUnauthorized() async {
        let api = StubTransport(
            .init(statusCode: 401, body: #"{"error":"Authentication failed."}"#)
        ).api(accessToken: "expired-token")

        await #expect(throws: APIError.unauthorized) {
            try await api.titleDetails(id: "rawg:891238")
        }
    }

    @Test
    func cancelledTransportThrowsCancellationError() async {
        let api = SoonrAPI(
            client: APIClient(
                configuration: .test,
                transport: { _ in
                    throw URLError(.cancelled)
                }
            )
        )

        await #expect(throws: CancellationError.self) {
            try await api.searchTitles(query: "halo")
        }
    }
}

private actor StubTransport {
    struct Response: Sendable {
        let statusCode: Int
        let body: String
    }

    private(set) var requests: [URLRequest] = []
    private let response: Response

    init(_ response: Response) {
        self.response = response
    }

    nonisolated func api(accessToken: String? = nil) -> SoonrAPI {
        SoonrAPI(
            client: APIClient(
                configuration: .test,
                accessToken: { accessToken },
                transport: { request in
                    try await self.send(request)
                }
            )
        )
    }

    private func send(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let url = try #require(request.url)
        let httpResponse = try #require(
            HTTPURLResponse(
                url: url, statusCode: response.statusCode, httpVersion: nil, headerFields: nil)
        )
        return (Data(response.body.utf8), httpResponse)
    }
}

private extension AppConfiguration {
    static let test = AppConfiguration(
        apiBaseURL: URL(string: "https://api.soonr.test")!,
        supabase: SupabaseConfiguration(
            url: URL(string: "https://project.supabase.test")!,
            publishableKey: "test-publishable-key"
        )
    )
}

private extension SoonrAPITests {
    static let fullDetailsJSON = #"""
        {
          "details": {
            "id": "rawg:891238",
            "kind": "game",
            "source": "rawg",
            "externalId": "891238",
            "slug": "hades-2",
            "name": "Hades II",
            "coverImageUrl": "https://media.rawg.io/media/games/hades-ii.jpg",
            "earliestReleaseDate": "2025-09-25",
            "platforms": [
              { "id": "rawg-platform:4", "name": "PC" },
              { "id": "rawg-platform:7", "name": "Nintendo Switch" }
            ],
            "rawgRating": 4.5,
            "rawgRatingsCount": 300,
            "rawgMetacritic": 95,
            "rawgAdded": 5000,
            "rawgReviewsCount": 310,
            "rawgSuggestionsCount": 400,
            "rawgRatingTop": 5,
            "description": "The first-ever sequel from Supergiant Games.",
            "genres": ["Action", "RPG"],
            "developers": ["Supergiant Games"],
            "publishers": ["Supergiant Games"],
            "websiteUrl": "https://www.supergiantgames.com/games/hades-ii/",
            "releases": [
              {
                "platformId": "rawg-platform:4",
                "platformName": "PC",
                "releaseDate": "2025-09-25",
                "releaseDatePrecision": "day"
              },
              {
                "platformId": "rawg-platform:7",
                "platformName": "Nintendo Switch",
                "releaseDate": null,
                "releaseDatePrecision": "unknown"
              }
            ]
          },
          "isInWatchlist": false
        }
        """#

    static let sparseDetailsJSON = #"""
        {
          "details": {
            "id": "rawg:274755",
            "kind": "game",
            "source": "rawg",
            "externalId": "274755",
            "slug": "hades-2018",
            "name": "Hades",
            "coverImageUrl": null,
            "earliestReleaseDate": "2020-09-17",
            "platforms": [{ "id": "rawg-platform:4", "name": "PC" }],
            "rawgRating": null,
            "rawgRatingsCount": null,
            "rawgMetacritic": null,
            "rawgAdded": null,
            "rawgReviewsCount": null,
            "rawgSuggestionsCount": null,
            "rawgRatingTop": null,
            "description": null,
            "genres": [],
            "developers": [],
            "publishers": [],
            "websiteUrl": null,
            "releases": []
          },
          "isInWatchlist": false
        }
        """#

    static let homeDiscoveryJSON = #"""
        {
          "upcoming": [
            {
              "id": "rawg:662318",
              "kind": "game",
              "source": "rawg",
              "externalId": "662318",
              "slug": "wolverine-2022",
              "name": "Marvel's Wolverine",
              "coverImageUrl": "https://media.rawg.io/media/games/28d/wolverine.jpg",
              "earliestReleaseDate": "2026-09-15",
              "platforms": [{ "id": "rawg-platform:187", "name": "PlayStation 5" }],
              "rawgRating": null,
              "rawgRatingsCount": null,
              "rawgMetacritic": null,
              "rawgAdded": null,
              "rawgReviewsCount": null,
              "rawgSuggestionsCount": null,
              "rawgRatingTop": null
            }
          ],
          "latest": [
            {
              "id": "rawg:274755",
              "kind": "game",
              "source": "rawg",
              "externalId": "274755",
              "slug": "hades-2018",
              "name": "Hades",
              "coverImageUrl": null,
              "earliestReleaseDate": "2020-09-17",
              "platforms": [],
              "rawgRating": null,
              "rawgRatingsCount": null,
              "rawgMetacritic": null,
              "rawgAdded": null,
              "rawgReviewsCount": null,
              "rawgSuggestionsCount": null,
              "rawgRatingTop": null
            }
          ],
          "popular": []
        }
        """#

    static let searchJSON = #"""
        {
          "query": "hades",
          "results": [
            {
              "id": "rawg:274755",
              "kind": "game",
              "source": "rawg",
              "externalId": "274755",
              "slug": "hades-2018",
              "name": "Hades",
              "coverImageUrl": null,
              "earliestReleaseDate": "2020-09-17",
              "platforms": [],
              "rawgRating": null,
              "rawgRatingsCount": null,
              "rawgMetacritic": null,
              "rawgAdded": null,
              "rawgReviewsCount": null,
              "rawgSuggestionsCount": null,
              "rawgRatingTop": null
            }
          ],
          "totalCount": 1,
          "page": 1,
          "limit": 20,
          "hasMore": false
        }
        """#
}
