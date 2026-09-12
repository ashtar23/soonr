import Foundation

struct FieldAvailability: Decodable, Equatable, Sendable {
    enum Reason: String, Equatable, Sendable {
        case taken
        case invalid
        case reserved
        case unknown
    }

    let available: Bool
    let reason: Reason?
}

extension FieldAvailability.Reason: Decodable {
    init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: rawValue) ?? .unknown
    }
}

/// The API reports which field conflicted in its message only, so the caller
/// cannot attribute a conflict to the email or the username.
enum SignUpFailure: Error, Equatable, LocalizedError {
    case conflict(String)
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case let .conflict(message), let .invalid(message):
            message
        }
    }
}

protocol AccountCreating: Sendable {
    func emailAvailability(email: String) async throws -> FieldAvailability
    func usernameAvailability(username: String) async throws -> FieldAvailability
    func signUp(email: String, password: String, username: String) async throws
}
