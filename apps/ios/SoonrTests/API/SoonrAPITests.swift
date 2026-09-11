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
        let client = APIClient(configuration: .test) { _ in
            Issue.record("Building a request must not send it.")
            throw URLError(.badURL)
        }

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
    func cancelledTransportThrowsCancellationError() async {
        let api = SoonrAPI(
            client: APIClient(configuration: .test) { _ in
                throw URLError(.cancelled)
            }
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

    nonisolated func api() -> SoonrAPI {
        SoonrAPI(
            client: APIClient(configuration: .test) { request in
                try await self.send(request)
            }
        )
    }

    private func send(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let url = try #require(request.url)
        let httpResponse = try #require(
            HTTPURLResponse(url: url, statusCode: response.statusCode, httpVersion: nil, headerFields: nil)
        )
        return (Data(response.body.utf8), httpResponse)
    }
}

private extension AppConfiguration {
    static let test = AppConfiguration(
        apiBaseURL: URL(string: "https://api.soonr.test")!,
        supabasePublishableKey: "test-publishable-key"
    )
}

private extension SoonrAPITests {
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
