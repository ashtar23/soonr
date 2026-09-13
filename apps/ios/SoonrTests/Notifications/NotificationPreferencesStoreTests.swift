import Foundation
import Testing

@testable import Soonr

@MainActor
@Suite(.tags(.networking))
struct NotificationPreferencesStoreTests {
    @Test
    func loadShowsWhatTheServerHasSaved() async {
        let model = NotificationPreferencesStore(
            notifications: StubPreferences(stored: .everything)
        )

        await model.load()

        #expect(model.state == .loaded(.everything))
    }

    @Test
    func failureIsReportedAndRetryRecovers() async {
        let preferences = StubPreferences(stored: .everything, failingLoads: 1)
        let model = NotificationPreferencesStore(notifications: preferences)

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
    func aPushedCopyIsAdoptedWhenNothingIsPending() async {
        let preferences = StubPreferences(stored: .everything)
        let model = await loaded(preferences)

        await model.apply(.onlyOnTheDay)

        #expect(model.state == .loaded(.onlyOnTheDay))
    }

    /// The pushed copy is usually the echo of this device's own save. Landing
    /// it while a switch the viewer has just moved is still on its way would
    /// flip that switch back under their finger.
    @Test
    func aPushedCopyIsDeclinedWhileALocalEditIsStillPending() async {
        let preferences = StubPreferences(stored: .everything)
        let model = await loaded(preferences)

        model.edit { $0.channels.inApp = false }
        await model.apply(.everything)

        #expect(model.preferences?.channels.inApp == false)
    }

    /// An event without a readable copy says only that something moved.
    @Test
    func aPushedEventWithoutACopyRefetches() async {
        let preferences = StubPreferences(stored: .everything)
        let model = await loaded(preferences)

        await model.apply(nil)

        #expect(await preferences.loads == 2)
    }

    /// Refetching behind a screen that already shows preferences must not drop
    /// it back to a spinner.
    @Test
    func refetchingDoesNotFlashTheLoadingState() async {
        let preferences = StubPreferences(stored: .everything)
        let model = await loaded(preferences)

        async let applied: Void = model.apply(nil)
        #expect(model.state == .loaded(.everything))
        await applied
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

    @Test
    func timingPresetsKeepTheirOrderHoweverTheyAreAdded() {
        var preferences = NotificationPreferences.onlyOnTheDay

        preferences.toggleTimingPreset(.days7Before)
        preferences.toggleTimingPreset(.days30Before)

        #expect(preferences.timingPresets == [.days30Before, .days7Before, .onDay])
    }

    /// An empty list is not a state the server keeps: it answers one with its
    /// own default, so the checkmark came straight back.
    @Test
    func theLastTimingPresetCannotBeCleared() {
        var preferences = NotificationPreferences.onlyOnTheDay

        preferences.toggleTimingPreset(.onDay)

        #expect(preferences.timingPresets == [.onDay])
    }

    @Test
    func anyPresetCanBeTheLastOneStanding() {
        var preferences = NotificationPreferences.everything

        preferences.toggleTimingPreset(.onDay)
        preferences.toggleTimingPreset(.days7Before)

        #expect(preferences.timingPresets == [.days7Before])
    }

    /// The store outlives the screen now, so signing out has to drop what it
    /// holds instead of showing it to the next account.
    @Test
    func signingOutDropsOneAccountsSettingsAndLoadsAgain() async {
        let preferences = StubPreferences(stored: .everything)
        let model = await loaded(preferences)

        model.edit { $0.channels.inApp = false }
        model.clear()

        #expect(model.state == .loading)
        #expect(model.preferences == nil)

        await model.load()
        #expect(model.state == .loaded(.everything))
        #expect(await preferences.saved.isEmpty)
    }

    /// A save cannot start until the screen knows what it is editing.
    private func loaded(_ preferences: StubPreferences) async -> NotificationPreferencesStore {
        let model = NotificationPreferencesStore(
            notifications: preferences,
            // Long enough that only an explicit flush sends anything, so the
            // test never races the timer.
            saveDelay: .seconds(60)
        )
        await model.load()
        return model
    }
}

private actor StubPreferences: NotificationPreferencesProviding {
    private(set) var saved: [NotificationPreferences] = []
    private(set) var loads = 0

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
        loads += 1

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
