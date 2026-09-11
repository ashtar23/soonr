import Foundation

protocol TitleSearching: Sendable {
    func searchTitles(query: String) async throws -> [TitleSummary]
}

enum APIError: Error, LocalizedError, Sendable {
    case invalidRequest
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "Soonr couldn't create that request."
        case .invalidResponse:
            "Soonr received an invalid response."
        case let .requestFailed(_, message):
            message
        case .invalidPayload:
            "Soonr couldn't read the search results."
        }
    }
}

struct SoonrAPI: TitleSearching, Sendable {
    static let live = SoonrAPI(configuration: .live)

    private let configuration: AppConfiguration
    private let session: URLSession

    init(
        configuration: AppConfiguration,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    func searchTitles(query: String) async throws -> [TitleSummary] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedQuery.count >= 2 else {
            return []
        }

        guard var components = URLComponents(
            url: configuration.apiBaseURL.appending(path: "titles"),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidRequest
        }

        components.queryItems = [
            URLQueryItem(name: "query", value: normalizedQuery),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "limit", value: "20"),
        ]

        guard let url = components.url else {
            throw APIError.invalidRequest
        }

        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let publishableKey = configuration.supabasePublishableKey {
            request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
            throw APIError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: errorResponse?.error ?? "Search failed. Please try again."
            )
        }

        do {
            return try JSONDecoder().decode(TitleSearchResponse.self, from: data).results
        } catch {
            throw APIError.invalidPayload
        }
    }
}

private struct TitleSearchResponse: Decodable {
    let results: [TitleSummary]
}

private struct APIErrorResponse: Decodable {
    let error: String
}
