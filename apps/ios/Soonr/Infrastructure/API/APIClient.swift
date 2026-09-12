import Foundation

enum APIError: Error, Equatable, LocalizedError, Sendable {
    case invalidRequest
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)
    case invalidPayload
    /// The session was rejected, so the caller should ask the user to sign in
    /// again rather than showing a generic failure.
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "Soonr couldn't create that request."
        case .invalidResponse:
            "Soonr received an invalid response."
        case let .requestFailed(_, message):
            message
        case .invalidPayload:
            "Soonr couldn't read the response."
        case .unauthorized:
            "Your session has expired. Please sign in again."
        }
    }
}

/// Shared request behavior for `apps/api` endpoints: URL construction, headers,
/// status validation, decoding, and transport error normalization.
struct APIClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    /// Asked per request: the session refreshes in the background, so a token
    /// captured once goes stale.
    typealias AccessTokenProvider = @Sendable () async -> String?

    enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case delete = "DELETE"
    }

    private let configuration: AppConfiguration
    private let transport: Transport
    private let accessToken: AccessTokenProvider

    init(
        configuration: AppConfiguration,
        accessToken: @escaping AccessTokenProvider = { nil },
        transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }
    ) {
        self.configuration = configuration
        self.accessToken = accessToken
        self.transport = transport
    }

    func get<Response: Decodable>(
        _ pathComponents: [String],
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        let data = try await send(.get, pathComponents, queryItems: queryItems)
        return try decode(data)
    }

    func post<Body: Encodable, Response: Decodable>(
        _ pathComponents: [String],
        body: Body
    ) async throws -> Response {
        let data = try await send(.post, pathComponents, body: try encode(body))
        return try decode(data)
    }

    /// For a write whose response body the caller does not read.
    func post<Body: Encodable>(_ pathComponents: [String], body: Body) async throws {
        _ = try await send(.post, pathComponents, body: try encode(body))
    }

    /// The response body is discarded: the endpoints we delete from report only
    /// that the resource is gone, which a 2xx status already tells us.
    func delete(_ pathComponents: [String]) async throws {
        _ = try await send(.delete, pathComponents)
    }

    private func send(
        _ method: Method,
        _ pathComponents: [String],
        queryItems: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> Data {
        var request = try makeRequest(
            method: method,
            pathComponents: pathComponents,
            queryItems: queryItems,
            body: body
        )
        if let token = await accessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode != 401 else {
            throw APIError.unauthorized
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
            throw APIError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: errorResponse?.error ?? "Something went wrong. Please try again."
            )
        }

        return data
    }

    func makeRequest(
        method: Method = .get,
        pathComponents: [String],
        queryItems: [URLQueryItem] = [],
        body: Data? = nil
    ) throws -> URLRequest {
        let url = pathComponents.reduce(configuration.apiBaseURL) { url, component in
            url.appending(component: component)
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidRequest
        }

        if queryItems.isEmpty == false {
            components.queryItems = queryItems
        }

        guard let requestURL = components.url else {
            throw APIError.invalidRequest
        }

        var request = URLRequest(url: requestURL, timeoutInterval: 8)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let publishableKey = configuration.supabasePublishableKey {
            request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        }

        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private func encode<Body: Encodable>(_ body: Body) throws -> Data {
        do {
            return try JSONEncoder().encode(body)
        } catch {
            throw APIError.invalidRequest
        }
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.invalidPayload
        }
    }
}

private struct APIErrorResponse: Decodable {
    let error: String
}
