import Foundation

/// The signed-in user, as the app needs it. Tokens stay out of application
/// state beyond the access token the API layer attaches to requests.
struct UserSession: Equatable, Sendable {
    let userID: String
    let email: String?
    let accessToken: String
}
