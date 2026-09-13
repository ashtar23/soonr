import Foundation

struct SoonrAPI:
    TitleSearching, TitleDetailsLoading, HomeDiscovering, WatchlistManaging, AccountCreating,
    NotificationsProviding, Sendable
{
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    init(configuration: AppConfiguration) {
        self.init(client: APIClient(configuration: configuration))
    }

    func searchTitles(query: String) async throws -> [TitleSummary] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedQuery.count >= 2 else {
            return []
        }

        let response: TitleSearchResponse = try await client.get(
            ["titles"],
            queryItems: [
                URLQueryItem(name: "query", value: normalizedQuery),
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "limit", value: "20"),
            ]
        )
        return response.results
    }

    func homeDiscovery() async throws -> HomeDiscovery {
        try await client.get(["home", "discovery"])
    }

    func titleDetails(id: String) async throws -> TitleDetailsResult? {
        do {
            return try await client.get(["titles", id])
        } catch APIError.requestFailed(404, _) {
            return nil
        }
    }

    func watchlist() async throws -> [WatchlistEntry] {
        let response: WatchlistResponse = try await client.get(["watchlist"])
        return response.items
    }

    func addToWatchlist(titleID: String) async throws {
        try await client.post(["watchlist"], body: WatchlistMutationBody(titleID: titleID))
    }

    func removeFromWatchlist(titleID: String) async throws {
        try await client.delete(["watchlist", titleID])
    }

    func notifications() async throws -> [NotificationRecord] {
        let response: NotificationListResponse = try await client.get(["notifications"])
        return response.items
    }

    func unreadNotificationCount() async throws -> Int {
        let response: UnreadCountResponse = try await client.get(["notifications", "unread-count"])
        return response.unreadCount
    }

    func markNotificationRead(id: String) async throws -> NotificationRecord {
        let response: MarkReadResponse = try await client.post(
            ["notifications", "read"],
            body: NotificationReadBody(notificationID: id)
        )
        return response.notification
    }

    func markAllNotificationsRead() async throws -> Int {
        let response: MarkAllReadResponse = try await client.post(
            ["notifications", "read-all"],
            body: EmptyBody()
        )
        return response.markedCount
    }

    func notificationPreferences() async throws -> NotificationPreferences {
        let response: PreferencesResponse = try await client.get(["notification-preferences"])
        return response.preferences
    }

    func updateNotificationPreferences(
        _ preferences: NotificationPreferences
    ) async throws -> NotificationPreferences {
        let response: PreferencesResponse = try await client.put(
            ["notification-preferences"],
            body: preferences
        )
        return response.preferences
    }

    func registerDevice(token: String, environment: PushEnvironment) async throws {
        let _: DeviceResponse = try await client.put(
            ["notifications", "devices"],
            body: DeviceRegistrationBody(
                token: token,
                platform: "ios",
                environment: environment
            )
        )
    }

    func unregisterDevice(token: String) async throws {
        try await client.delete(["notifications", "devices", token])
    }

    func emailAvailability(email: String) async throws -> FieldAvailability {
        try await client.get(
            ["auth", "email-availability"],
            queryItems: [URLQueryItem(name: "email", value: email)]
        )
    }

    func usernameAvailability(username: String) async throws -> FieldAvailability {
        try await client.get(
            ["profile", "username-availability"],
            queryItems: [URLQueryItem(name: "username", value: username)]
        )
    }

    func signUp(email: String, password: String, username: String) async throws {
        do {
            try await client.post(
                ["auth", "sign-up"],
                body: SignUpBody(email: email, password: password, username: username)
            )
        } catch APIError.requestFailed(409, let message) {
            throw SignUpFailure.conflict(message)
        } catch APIError.requestFailed(400, let message) {
            throw SignUpFailure.invalid(message)
        }
    }
}

private struct SignUpBody: Encodable {
    let email: String
    let password: String
    let username: String
}

/// The title travels in the body on add, and in the path on remove, which is
/// how `apps/api` defines the two routes.
private struct WatchlistMutationBody: Encodable {
    let titleID: String

    enum CodingKeys: String, CodingKey {
        case titleID = "titleId"
    }
}

private struct TitleSearchResponse: Decodable {
    let results: [TitleSummary]
}

/// `nextCursor` is ignored while the screen shows a single page.
private struct WatchlistResponse: Decodable {
    let items: [WatchlistEntry]
}

private struct NotificationListResponse: Decodable {
    let items: [NotificationRecord]
}

private struct UnreadCountResponse: Decodable {
    let unreadCount: Int
}

private struct MarkReadResponse: Decodable {
    let notification: NotificationRecord
}

private struct MarkAllReadResponse: Decodable {
    let markedCount: Int
}

private struct PreferencesResponse: Decodable {
    let preferences: NotificationPreferences
}

private struct NotificationReadBody: Encodable {
    let notificationID: String

    enum CodingKeys: String, CodingKey {
        case notificationID = "notificationId"
    }
}

/// The route takes no body, but a POST still sends one.
private struct EmptyBody: Encodable {}

private struct DeviceRegistrationBody: Encodable {
    let token: String
    let platform: String
    let environment: PushEnvironment
}

private struct DeviceResponse: Decodable {
    struct Device: Decodable {
        let token: String
    }

    let device: Device
}
