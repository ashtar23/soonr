import Foundation
import Testing

@testable import Soonr

@Suite(.tags(.networking))
struct NotificationsAPITests {
    /// The size is asked for rather than left to the server's default, so a
    /// change there cannot quietly resize every list in the app.
    @Test
    func theFirstPageAsksForASizeAndNoCursor() async throws {
        let transport = StubTransport(.init(statusCode: 200, body: Self.listJSON))

        _ = try await transport.api(accessToken: "token").notifications(after: nil)

        let query = try await queryItems(of: transport)
        #expect(query.first { $0.name == "limit" }?.value == "20")
        #expect(query.contains { $0.name == "cursor" } == false)
    }

    @Test
    func aLaterPageSendsBackTheCursorItWasGiven() async throws {
        let transport = StubTransport(.init(statusCode: 200, body: Self.listJSON))

        _ = try await transport.api(accessToken: "token").notifications(after: "cursor-2")

        let query = try await queryItems(of: transport)
        #expect(query.first { $0.name == "cursor" }?.value == "cursor-2")
    }

    /// Cursors are opaque and the server's to shape, so anything it sends must
    /// come back unchanged.
    @Test
    func theCursorSurvivesCharactersThatNeedEncoding() async throws {
        let transport = StubTransport(.init(statusCode: 200, body: Self.listJSON))
        let cursor = "2026-01-03T12:00:00.000Z|notification-1/+="

        _ = try await transport.api(accessToken: "token").notifications(after: cursor)

        let query = try await queryItems(of: transport)
        #expect(query.first { $0.name == "cursor" }?.value == cursor)
    }

    private func queryItems(of transport: StubTransport) async throws -> [URLQueryItem] {
        let request = try #require(await transport.requests.first)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return components.queryItems ?? []
    }

    @Test
    func notificationsDecodeWithWhatARowNeeds() async throws {
        let transport = StubTransport(.init(statusCode: 200, body: Self.listJSON))

        let notifications = try await transport.api(accessToken: "token")
            .notifications(after: nil).items

        let request = try #require(await transport.requests.first)
        #expect(request.url?.path(percentEncoded: false) == "/notifications")

        let first = try #require(notifications.first)
        #expect(first.id == "notification-1")
        #expect(first.eventType == .releaseApproaching)
        #expect(first.destinationTitleID == "rawg:274755")
        #expect(first.titleName == "Hades")
        #expect(first.message == "Hades arrives in 7 days.")
        #expect(first.isRead == false)
        #expect(notifications.last?.isRead == true)
    }

    /// An event type we do not know must not fail the whole list.
    @Test
    func anUnknownEventTypeStillDecodes() async throws {
        let body = Self.listJSON.replacingOccurrences(
            of: #""release_approaching""#,
            with: #""something_new""#
        )
        let api = StubTransport(.init(statusCode: 200, body: body)).api(accessToken: "token")

        #expect(try await api.notifications(after: nil).items.first?.eventType == .unknown)
    }

    @Test
    func theUnreadCountDecodes() async throws {
        let transport = StubTransport(.init(statusCode: 200, body: #"{"unreadCount":3}"#))

        let count = try await transport.api(accessToken: "token").unreadNotificationCount()

        let request = try #require(await transport.requests.first)
        #expect(request.url?.path(percentEncoded: false) == "/notifications/unread-count")
        #expect(count == 3)
    }

    @Test
    func markingOneReadSendsItsIdentifier() async throws {
        let transport = StubTransport(
            .init(statusCode: 200, body: #"{"notification":\#(Self.readNotificationJSON)}"#)
        )

        let notification = try await transport.api(accessToken: "token")
            .markNotificationRead(id: "notification-1")

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path(percentEncoded: false) == "/notifications/read")
        let body = try #require(request.httpBody)
        let sent = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(sent["notificationId"] == "notification-1")
        #expect(notification.isRead)
    }

    @Test
    func markingAllReadReportsHowMany() async throws {
        let transport = StubTransport(.init(statusCode: 200, body: #"{"markedCount":4}"#))

        let marked = try await transport.api(accessToken: "token").markAllNotificationsRead()

        let request = try #require(await transport.requests.first)
        #expect(request.url?.path(percentEncoded: false) == "/notifications/read-all")
        #expect(marked == 4)
    }

    @Test
    func preferencesDecode() async throws {
        let transport = StubTransport(.init(statusCode: 200, body: Self.preferencesJSON))

        let preferences = try await transport.api(accessToken: "token").notificationPreferences()

        let request = try #require(await transport.requests.first)
        #expect(request.url?.path(percentEncoded: false) == "/notification-preferences")
        #expect(preferences.channels.inApp)
        #expect(preferences.channels.push == false)
        #expect(preferences.events.releaseApproaching)
        #expect(preferences.timingPresets == [.onDay, .days7Before])
    }

    /// A preset the client cannot name is dropped rather than failing the
    /// payload, so the switches it does know still appear.
    @Test
    func anUnknownTimingPresetIsDropped() async throws {
        let body = Self.preferencesJSON.replacingOccurrences(
            of: #""days_7_before""#,
            with: #""days_3_before""#
        )
        let api = StubTransport(.init(statusCode: 200, body: body)).api(accessToken: "token")

        #expect(try await api.notificationPreferences().timingPresets == [.onDay])
    }

    @Test
    func updatingPreferencesPutsThemBack() async throws {
        let transport = StubTransport(.init(statusCode: 200, body: Self.preferencesJSON))
        let preferences = NotificationPreferences(
            channels: .init(inApp: true, push: false),
            events: .init(releaseDateChanged: false, releaseApproaching: true),
            timingPresets: [.onDay, .days7Before]
        )

        _ = try await transport.api(accessToken: "token")
            .updateNotificationPreferences(preferences)

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path(percentEncoded: false) == "/notification-preferences")

        let body = try #require(request.httpBody)
        let sent = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(sent["timingPresets"] as? [String] == ["on_day", "days_7_before"])
    }
}

private actor StubTransport {
    struct Response: Sendable {
        let statusCode: Int
        let body: String
    }

    private(set) var requests: [URLRequest] = []
    private let response: Response

    init(_ response: Response) {
        self.response = response
    }

    nonisolated func api(accessToken: String? = nil) -> SoonrAPI {
        SoonrAPI(
            client: APIClient(
                configuration: .test,
                accessToken: { accessToken },
                transport: { request in
                    try await self.send(request)
                }
            )
        )
    }

    private func send(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let url = try #require(request.url)
        let httpResponse = try #require(
            HTTPURLResponse(
                url: url, statusCode: response.statusCode, httpVersion: nil, headerFields: nil)
        )
        return (Data(response.body.utf8), httpResponse)
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

private extension NotificationsAPITests {
    static let readNotificationJSON = #"""
        {
          "id": "notification-1",
          "titleId": "rawg:274755",
          "eventType": "release_approaching",
          "destinationKind": "title",
          "destinationTitleId": "rawg:274755",
          "titleName": "Hades",
          "titleArtworkUrl": null,
          "message": "Hades arrives in 7 days.",
          "subtitle": "Coming soon",
          "payload": { "targetReleaseDate": "2026-01-10", "timingPreset": "days_7_before" },
          "createdAt": "2026-01-03T10:00:00.000Z",
          "readAt": "2026-01-03T11:00:00.000Z"
        }
        """#

    static let listJSON = #"""
        {
          "items": [
            {
              "id": "notification-1",
              "titleId": "rawg:274755",
              "eventType": "release_approaching",
              "destinationKind": "title",
              "destinationTitleId": "rawg:274755",
              "titleName": "Hades",
              "titleArtworkUrl": null,
              "message": "Hades arrives in 7 days.",
              "subtitle": "Coming soon",
              "payload": { "targetReleaseDate": "2026-01-10", "timingPreset": "days_7_before" },
              "createdAt": "2026-01-03T10:00:00.000Z",
              "readAt": null
            },
            {
              "id": "notification-2",
              "titleId": "rawg:3498",
              "eventType": "release_date_changed",
              "destinationKind": "title",
              "destinationTitleId": "rawg:3498",
              "titleName": "Grand Theft Auto VI",
              "titleArtworkUrl": "https://media.rawg.io/media/games/gta.jpg",
              "message": "Grand Theft Auto VI moved to Nov 19, 2026.",
              "subtitle": null,
              "payload": { "previousReleaseDate": "2026-05-26", "nextReleaseDate": "2026-11-19" },
              "createdAt": "2026-01-02T10:00:00.000Z",
              "readAt": "2026-01-02T12:00:00.000Z"
            }
          ],
          "nextCursor": null
        }
        """#

    static let preferencesJSON = #"""
        {
          "preferences": {
            "channels": { "inApp": true, "push": false },
            "events": { "releaseDateChanged": false, "releaseApproaching": true },
            "timingPresets": ["on_day", "days_7_before"],
            "updatedAt": "2026-01-01T10:00:00.000Z"
          }
        }
        """#
}
