import Foundation

/// Why something failed, kept in state so a screen can offer the right action:
/// a retry is useless for a rejected session, and "check your connection" is
/// wrong for a server fault.
enum FailureReason: Equatable, Sendable {
    case offline
    case timedOut
    case unauthorized
    case server(message: String)
    case unreadable
    case unknown(message: String)

    init(_ error: any Error) {
        switch error {
        case let apiError as APIError:
            self = FailureReason(apiError)
        case let urlError as URLError:
            self = FailureReason(urlError)
        default:
            let message = error.localizedDescription
            self = message.isEmpty ? .unreadable : .unknown(message: message)
        }
    }

    private init(_ error: APIError) {
        switch error {
        case .unauthorized:
            self = .unauthorized
        case let .requestFailed(_, message):
            self = .server(message: message)
        case .invalidPayload, .invalidResponse, .invalidRequest:
            self = .unreadable
        }
    }

    private init(_ error: URLError) {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
            .internationalRoamingOff:
            self = .offline
        case .timedOut, .cannotConnectToHost, .cannotFindHost:
            self = .timedOut
        default:
            self = .unknown(message: error.localizedDescription)
        }
    }

    /// For a message shown inline, beside a field or under a form.
    var message: String {
        switch self {
        case .offline:
            "You appear to be offline."
        case .timedOut:
            "The server took too long to answer."
        case .unauthorized:
            "Your session has expired. Please sign in again."
        case let .server(message), let .unknown(message):
            message
        case .unreadable:
            "Soonr couldn't read the response."
        }
    }

    /// A rejected session is not worth retrying; signing in again is.
    var isRetryable: Bool {
        self != .unauthorized
    }
}
