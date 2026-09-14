import Foundation

/// Mirrors the pattern `apps/api` validates with, so obviously malformed input
/// is answered without a round trip. The server stays the authority: it also
/// owns the reserved names, which are deliberately not duplicated here.
enum UsernameRule {
    static let maximumLength = 30

    enum Problem: Equatable {
        case tooLong
        case malformed
    }

    static func normalize(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func problem(with username: String) -> Problem? {
        let normalized = normalize(username)
        guard normalized.count <= maximumLength else {
            return .tooLong
        }

        let pattern = /^(?!.*[._]{2})[a-z0-9](?:[a-z0-9._]{1,28}[a-z0-9])?$/
        return normalized.wholeMatch(of: pattern) == nil ? .malformed : nil
    }

    /// Worded once, so signing up and changing a username later say the same
    /// thing about the same name.
    static func message(for problem: Problem) -> String {
        switch problem {
        case .tooLong: "Usernames can be at most \(maximumLength) characters."
        case .malformed: "Usernames use letters, numbers, dots and underscores."
        }
    }

    static func message(for reason: FieldAvailability.Reason?) -> String {
        switch reason {
        case .reserved: "That username isn't available."
        case .invalid: "That username can't be used."
        case .taken, .unknown, .none: "That username is already taken."
        }
    }
}
