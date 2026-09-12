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
        var request = try makeRequest(pathComponents: pathComponents, queryItems: queryItems)
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

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.invalidPayload
        }
    }

    func makeRequest(
        pathComponents: [String],
        queryItems: [URLQueryItem] = []
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
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let publishableKey = configuration.supabasePublishableKey {
            request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        }

        return request
    }
}

private struct APIErrorResponse: Decodable {
    let error: String
}
