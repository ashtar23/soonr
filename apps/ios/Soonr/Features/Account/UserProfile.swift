import Foundation

/// Who someone is in Soonr, as distinct from how they sign in.
///
/// Supabase owns the account — credentials, sessions, the email. This is the
/// part the app owns: the name people see, and who gets to see what.
struct UserProfile: Decodable, Equatable, Sendable {
    let userID: String
    /// Absent on accounts made before signup asked for one, which is also why
    /// changing it has to be possible.
    let username: String?
    let displayName: String?
    let avatarURL: URL?
    let bio: String?
    let watchlistVisibility: WatchlistVisibility

    /// What it says when there is nothing to say: a name, then a handle, then
    /// the only thing every account is guaranteed to have.
    func title(fallback: String) -> String {
        displayName ?? username.map { "@\($0)" } ?? fallback
    }

    func setting(watchlistVisibility: WatchlistVisibility) -> UserProfile {
        UserProfile(
            userID: userID,
            username: username,
            displayName: displayName,
            avatarURL: avatarURL,
            bio: bio,
            watchlistVisibility: watchlistVisibility
        )
    }

    private enum CodingKeys: String, CodingKey {
        case userID = "userId"
        case username
        case displayName
        case avatarURL = "avatarUrl"
        case bio
        case watchlistVisibility
    }
}

enum WatchlistVisibility: String, Codable, CaseIterable, Sendable {
    case `private`
    case friends
    case `public`

    var label: String {
        switch self {
        case .private: "Only me"
        case .friends: "Friends"
        case .public: "Everyone"
        }
    }

    var explanation: String {
        switch self {
        case .private: "Nobody else can see what you are tracking."
        case .friends: "People you follow who follow you back can see it."
        case .public: "Anyone who finds your profile can see it."
        }
    }
}

/// The parts of a profile its owner can change.
///
/// Sent whole rather than as a patch: this is a form, and the form holds every
/// field. Emptying one clears it — the server reads blank as nothing rather
/// than storing the spaces.
struct ProfileEdit: Encodable, Equatable, Sendable {
    var username: String
    var displayName: String
    var bio: String
    var watchlistVisibility: WatchlistVisibility

    init(from profile: UserProfile) {
        username = profile.username ?? ""
        displayName = profile.displayName ?? ""
        bio = profile.bio ?? ""
        watchlistVisibility = profile.watchlistVisibility
    }
}

/// How many people are connected to a profile, which is what makes a profile
/// read as a person rather than as a form about one.
struct ProfileCounts: Decodable, Equatable, Sendable {
    let friends: Int
    let followers: Int
    let following: Int
}

/// A profile and its counts, which arrive in the same response. Kept apart
/// because only the profile comes back from an edit.
struct ProfileOverview: Equatable, Sendable {
    let profile: UserProfile
    let counts: ProfileCounts
}

/// Reading and changing the signed-in account's own profile.
protocol ProfileEditing: Sendable {
    func profile(userID: String) async throws -> ProfileOverview
    func updateProfile(_ edit: ProfileEdit) async throws -> UserProfile
}
