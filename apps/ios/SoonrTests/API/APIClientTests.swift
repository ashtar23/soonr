import Foundation
import Testing

@testable import Soonr

/// Request shaping for the write methods the watchlist needs. Endpoint
/// behavior is covered by `SoonrAPITests`.
@Suite(.tags(.networking))
struct APIClientTests {
    @Test
    func postSendsTheEncodedBodyAsJSON() async throws {
        let transport = StubTransport(.json(201, #"{"item":{"id":"1"}}"#))

        let _: CreatedItem = try await transport.client()
            .post(["watchlist"], body: WatchlistMutation(titleID: "rawg:274755"))

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path(percentEncoded: false) == "/watchlist")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "apikey") == "test-publishable-key")

        let body = try #require(request.httpBody)
        #expect(
            try JSONDecoder().decode(WatchlistMutation.self, from: body).titleID == "rawg:274755")
    }

    @Test
    func postDecodesACreatedResource() async throws {
        let transport = StubTransport(.json(201, #"{"item":{"id":"watchlist-1"}}"#))

        let created: CreatedItem = try await transport.client()
            .post(["watchlist"], body: WatchlistMutation(titleID: "rawg:1"))

        #expect(created.item.id == "watchlist-1")
    }

    /// A GET must not have picked up a body or a content type from the
    /// refactor that introduced writes.
    @Test
    func getStillSendsNoBody() async throws {
        let transport = StubTransport(.json(200, #"{"item":{"id":"1"}}"#))

        let _: CreatedItem = try await transport.client().get(["watchlist"])

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
    }

    /// A server reading query parameters as form data turns an unescaped "+"
    /// into a space, which loses an email alias and breaks a search for "C++".
    @Test
    func plusInAQueryValueIsEncoded() async throws {
        let transport = StubTransport(.json(200, #"{"item":{"id":"1"}}"#))

        let _: CreatedItem = try await transport.client()
            .get(
                ["auth", "email-availability"],
                queryItems: [URLQueryItem(name: "email", value: "someone+tag@example.com")]
            )

        let request = try #require(await transport.requests.first)
        let query = try #require(request.url?.query(percentEncoded: true))
        #expect(query.contains("%2B"))
        #expect(query.contains("+") == false)
    }

    @Test
    func deleteTargetsTheResourceWithAnEncodedIdentifier() async throws {
        let transport = StubTransport(.json(200, #"{"removed":true}"#))

        try await transport.client().delete(["watchlist", "rawg:274755"])

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path(percentEncoded: false) == "/watchlist/rawg:274755")
        #expect(request.httpBody == nil)
    }

    /// Nothing reads the delete response, so a body-less success must still
    /// count as one.
    @Test
    func deleteAcceptsAnEmptyResponseBody() async throws {
        let transport = StubTransport(StubTransport.Response(statusCode: 204))

        try await transport.client().delete(["watchlist", "rawg:1"])

        #expect(await transport.requests.count == 1)
    }

    @Test
    func writesCarryTheSession() async throws {
        let transport = StubTransport(.json(201, #"{"item":{"id":"1"}}"#))

        let _: CreatedItem = try await transport.client(accessToken: "session-token")
            .post(["watchlist"], body: WatchlistMutation(titleID: "rawg:1"))

        let request = try #require(await transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer session-token")
    }

    @Test
    func aRejectedWriteIsReportedAsUnauthorized() async {
        let transport = StubTransport(.json(401, #"{"error":"Authentication failed."}"#))

        await #expect(throws: APIError.unauthorized) {
            let _: CreatedItem = try await transport.client(accessToken: "expired")
                .post(["watchlist"], body: WatchlistMutation(titleID: "rawg:1"))
        }
    }

    /// A rejected session has to reach the app root, or a screen is left
    /// offering a retry that can only fail again.
    @Test
    func aRejectedSessionIsReported() async {
        let transport = StubTransport(.json(401, #"{"error":"Authentication failed."}"#))
        let rejections = Counter()

        await #expect(throws: APIError.unauthorized) {
            let _: CreatedItem =
                try await transport
                .client(accessToken: "expired", onUnauthorized: { rejections.increment() })
                .post(["watchlist"], body: WatchlistMutation(titleID: "rawg:1"))
        }

        #expect(rejections.value == 1)
    }

    /// The bug this exists for: a viewer came back after an hour and was
    /// signed out. One 401 is not proof the session is over — the token may
    /// have gone stale, and the server answers its own failure to reach
    /// Supabase with a 401 as well.
    @Test
    func aStaleTokenIsRefreshedAndTheRequestTriedAgain() async throws {
        let transport = StubTransport(
            .json(401, #"{"error":"Authentication failed."}"#),
            .json(200, #"{"item":{"id":"1"}}"#)
        )
        let rejections = Counter()

        let _: CreatedItem =
            try await transport
            .client(
                accessToken: "stale",
                refreshedAccessToken: "fresh",
                onUnauthorized: { rejections.increment() }
            )
            .get(["watchlist"])

        #expect(rejections.value == 0)
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer fresh")
    }

    @Test
    func aFreshTokenRejectedTooEndsTheSession() async {
        let transport = StubTransport(.json(401, #"{"error":"Authentication failed."}"#))
        let rejections = Counter()

        await #expect(throws: APIError.unauthorized) {
            let _: CreatedItem =
                try await transport
                .client(
                    accessToken: "stale",
                    refreshedAccessToken: "fresh",
                    onUnauthorized: { rejections.increment() }
                )
                .get(["watchlist"])
        }

        #expect(rejections.value == 1)
        #expect(await transport.requests.count == 2)
    }

    /// Nothing left to refresh with means the session really is over.
    @Test
    func aSessionThatCannotBeRefreshedEndsWithoutASecondRequest() async {
        let transport = StubTransport(.json(401, #"{"error":"Authentication failed."}"#))
        let rejections = Counter()

        await #expect(throws: APIError.unauthorized) {
            let _: CreatedItem =
                try await transport
                .client(accessToken: "stale", onUnauthorized: { rejections.increment() })
                .get(["watchlist"])
        }

        #expect(rejections.value == 1)
        #expect(await transport.requests.count == 1)
    }

    /// A guest is not signed in to begin with, so a 401 on a request that
    /// carried no session must not sign anyone out.
    @Test
    func aGuestsRejectionIsNotASessionEnding() async {
        let transport = StubTransport(.json(401, #"{"error":"Authorization is required."}"#))
        let rejections = Counter()

        await #expect(throws: APIError.unauthorized) {
            let _: CreatedItem =
                try await transport
                .client(onUnauthorized: { rejections.increment() })
                .get(["watchlist"])
        }

        #expect(rejections.value == 0)
    }

    @Test
    func aSuccessfulRequestReportsNoRejection() async throws {
        let transport = StubTransport(.json(200, #"{"item":{"id":"1"}}"#))
        let rejections = Counter()

        let _: CreatedItem =
            try await transport
            .client(accessToken: "token", onUnauthorized: { rejections.increment() })
            .get(["watchlist"])

        #expect(rejections.value == 0)
    }

    @Test
    func aFailedWriteSurfacesTheServerMessage() async {
        let transport = StubTransport(.json(400, #"{"error":"titleId is required."}"#))

        await #expect(
            throws: APIError.requestFailed(statusCode: 400, message: "titleId is required.")
        ) {
            let _: CreatedItem = try await transport.client()
                .post(["watchlist"], body: WatchlistMutation(titleID: ""))
        }
    }

    @Test
    func aMalformedCreatedPayloadThrowsInvalidPayload() async {
        let transport = StubTransport(.json(201, #"{"item":{"id":7}}"#))

        await #expect(throws: APIError.invalidPayload) {
            let _: CreatedItem = try await transport.client()
                .post(["watchlist"], body: WatchlistMutation(titleID: "rawg:1"))
        }
    }

    @Test
    func aCancelledWriteThrowsCancellationError() async {
        let client = APIClient(
            configuration: .test,
            transport: { _ in
                throw URLError(.cancelled)
            }
        )

        await #expect(throws: CancellationError.self) {
            try await client.delete(["watchlist", "rawg:1"])
        }
    }
}

/// Stand-ins for the payloads the watchlist commits will introduce, so this
/// suite tests the client rather than a feature's model.
private struct WatchlistMutation: Codable {
    let titleID: String

    enum CodingKeys: String, CodingKey {
        case titleID = "titleId"
    }
}

/// The handler is called from whatever context the request finished on, so the
/// count is guarded.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

private struct CreatedItem: Decodable {
    struct Item: Decodable {
        let id: String
    }

    let item: Item
}

private actor StubTransport {
    struct Response: Sendable {
        let statusCode: Int
        var body = Data()

        static func json(_ statusCode: Int, _ body: String) -> Response {
            Response(statusCode: statusCode, body: Data(body.utf8))
        }
    }

    private(set) var requests: [URLRequest] = []
    /// The last one answers every request after it, so a test that cares about
    /// one exchange states one response.
    private var responses: [Response]

    init(_ responses: Response...) {
        self.responses = responses
    }

    nonisolated func client(
        accessToken: String? = nil,
        refreshedAccessToken: String? = nil,
        onUnauthorized: @escaping @Sendable () -> Void = {}
    ) -> APIClient {
        APIClient(
            configuration: .test,
            accessToken: { accessToken },
            refreshedAccessToken: { refreshedAccessToken },
            onUnauthorized: onUnauthorized,
            transport: { request in
                try await self.send(request)
            }
        )
    }

    private func send(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let response = responses.count > 1 ? responses.removeFirst() : responses[0]
        let url = try #require(request.url)
        let httpResponse = try #require(
            HTTPURLResponse(
                url: url, statusCode: response.statusCode, httpVersion: nil, headerFields: nil)
        )
        return (response.body, httpResponse)
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
