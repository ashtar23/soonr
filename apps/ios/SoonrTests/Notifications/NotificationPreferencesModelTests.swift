import Foundation
import Testing

@testable import Soonr

@MainActor
@Suite(.tags(.networking))
struct NotificationPreferencesModelTests {
    @Test
    func loadShowsWhatTheServerHasSaved() async {
        let model = NotificationPreferencesModel(
            notifications: StubPreferences(stored: .everything)
        )

        await model.load()

        #expect(model.state == .loaded(.everything))
    }

    @Test
    func failureIsReportedAndRetryRecovers() async {
        let preferences = StubPreferences(stored: .everything, failingLoads: 1)
        let model = NotificationPreferencesModel(notifications: preferences)

        await model.load()
        #expect(model.state == .failed(.offline))

        await model.retry()
        #expect(model.state == .loaded(.everything))
    }

    @Test
    func aSwitchMovesBeforeTheSaveIsSent() async {
        let preferences = StubPreferences(stored: .everything)
        let model = await loaded(preferences)

        model.edit { $0.channels.inApp = false }

        #expect(model.preferences?.channels.inApp == false)
        #expect(await preferences.saved.isEmpty)
    }

    @Test
    func aBurstOfTapsIsSentOnce() async {
        let preferences = StubPreferences(stored: .everything)
        let model = await loaded(preferences)

        model.edit { $0.events.releaseApproaching = false }
        model.edit { $0.events.releaseDateChanged = false }
        await model.flush()

        #expect(await preferences.saved.count == 1)
        #expect(await preferences.saved.last?.events.releaseApproaching == false)
        #expect(await preferences.saved.last?.events.releaseDateChanged == false)
    }

    @Test
    func aRejectedSaveGoesBackToWhatTheServerConfirmed() async {
        let preferences = StubPreferences(stored: .everything, failingSaves: true)
        let model = await loaded(preferences)

        model.edit { $0.channels.inApp = false }
        await model.flush()

        #expect(model.preferences == .everything)
        #expect(model.saveFailure == .offline)
    }

    @Test
    func theScreenAdoptsWhatTheServerAcknowledged() async {
        let preferences = StubPreferences(stored: .everything, acknowledging: .onlyOnTheDay)
        let model = await loaded(preferences)

        model.edit { $0.timingPresets = [.onDay] }
        await model.flush()

        #expect(model.state == .loaded(.onlyOnTheDay))
    }

    @Test
    func flushingWithNothingPendingSendsNothing() async {
        let preferences = StubPreferences(stored: .everything)
        let model = await loaded(preferences)

        await model.flush()

        #expect(await preferences.saved.isEmpty)
    }

    /// A save cannot start until the screen knows what it is editing.
    private func loaded(_ preferences: StubPreferences) async -> NotificationPreferencesModel {
        let model = NotificationPreferencesModel(
            notifications: preferences,
            // Long enough that only an explicit flush sends anything, so the
            // test never races the timer.
            saveDelay: .seconds(60)
        )
        await model.load()
        return model
    }
}

private actor StubPreferences: NotificationsProviding {
    private(set) var saved: [NotificationPreferences] = []

    private let stored: NotificationPreferences
    private let acknowledging: NotificationPreferences?
    private let failingSaves: Bool
    private var failingLoads: Int

    init(
        stored: NotificationPreferences,
        acknowledging: NotificationPreferences? = nil,
        failingLoads: Int = 0,
        failingSaves: Bool = false
    ) {
        self.stored = stored
        self.acknowledging = acknowledging
        self.failingLoads = failingLoads
        self.failingSaves = failingSaves
    }

    func notificationPreferences() async throws -> NotificationPreferences {
        if failingLoads > 0 {
            failingLoads -= 1
            throw URLError(.notConnectedToInternet)
        }

        return stored
    }

    func updateNotificationPreferences(
        _ preferences: NotificationPreferences
    ) async throws -> NotificationPreferences {
        saved.append(preferences)
        if failingSaves {
            throw URLError(.notConnectedToInternet)
        }

        return acknowledging ?? preferences
    }

    func notifications() async throws -> [NotificationRecord] {
        []
    }

    func unreadNotificationCount() async throws -> Int {
        0
    }

    func markNotificationRead(id: String) async throws -> NotificationRecord {
        .previewUnread
    }

    func markAllNotificationsRead() async throws -> Int {
        0
    }
}

private extension NotificationPreferences {
    static let everything = NotificationPreferences(
        channels: Channels(inApp: true, push: false),
        events: Events(releaseDateChanged: true, releaseApproaching: true),
        timingPresets: [.days7Before, .onDay]
    )

    static let onlyOnTheDay = NotificationPreferences(
        channels: Channels(inApp: true, push: false),
        events: Events(releaseDateChanged: true, releaseApproaching: true),
        timingPresets: [.onDay]
    )
}
