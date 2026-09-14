import Foundation
import Testing

@testable import Soonr

@MainActor
@Suite(.tags(.networking))
struct ProfileStoreTests {
    private let userID = "user-1"

    private func profile(
        username: String? = "reader",
        displayName: String? = "A Reader",
        bio: String? = nil
    ) -> UserProfile {
        UserProfile(
            userID: "user-1",
            username: username,
            displayName: displayName,
            avatarURL: nil,
            bio: bio,
            watchlistVisibility: .friends
        )
    }

    @Test
    func loadShowsTheProfileTheServerHolds() async {
        let store = ProfileStore(profiles: StubProfiles(profile: profile()))

        await store.load(userID: userID)

        #expect(store.state == .loaded(profile()))
    }

    @Test
    func failureIsReportedAndRetryRecovers() async {
        let profiles = StubProfiles(profile: profile(), failingLoads: 1)
        let store = ProfileStore(profiles: profiles)

        await store.load(userID: userID)
        #expect(store.state == .failed(.offline))

        await store.retry(userID: userID)
        #expect(store.state == .loaded(profile()))
    }

    /// Opening the tab again should not refetch what is already shown.
    @Test
    func asecondLoadLeavesAnAlreadyLoadedProfileAlone() async {
        let profiles = StubProfiles(profile: profile())
        let store = ProfileStore(profiles: profiles)
        await store.load(userID: userID)

        await store.load(userID: userID)

        #expect(await profiles.loads == 1)
    }

    // MARK: - Saving

    @Test
    func savingKeepsWhatTheServerAcknowledged() async {
        let saved = profile(username: "readerone", displayName: "Reader One")
        let profiles = StubProfiles(profile: profile(), acknowledging: saved)
        let store = ProfileStore(profiles: profiles)
        await store.load(userID: userID)

        let kept = await store.save(ProfileEdit(from: saved))

        #expect(kept)
        #expect(store.state == .loaded(saved))
        #expect(store.saveFailure == nil)
    }

    /// A username can be refused by a rule or by somebody already having it,
    /// and the reason is the only thing worth showing.
    @Test
    func arefusedSaveReportsWhyAndKeepsTheProfileAsItWas() async {
        let profiles = StubProfiles(profile: profile(), failingSaves: true)
        let store = ProfileStore(profiles: profiles)
        await store.load(userID: userID)

        let kept = await store.save(ProfileEdit(from: profile(username: "taken")))

        #expect(kept == false)
        #expect(store.saveFailure != nil)
        // The screen still shows what the server holds, not what was refused.
        #expect(store.state == .loaded(profile()))
    }

    @Test
    func anearlierRefusalIsClearedByTheNextAttempt() async {
        let profiles = StubProfiles(profile: profile(), failingSaves: true)
        let store = ProfileStore(profiles: profiles)
        await store.load(userID: userID)
        _ = await store.save(ProfileEdit(from: profile()))
        #expect(store.saveFailure != nil)

        await profiles.stopFailingSaves()
        _ = await store.save(ProfileEdit(from: profile()))

        #expect(store.saveFailure == nil)
    }

    /// A double tap on Save is one save.
    @Test
    func asecondSaveWhileOneIsInFlightIsRefused() async {
        let profiles = StubProfiles(profile: profile())
        let store = ProfileStore(profiles: profiles)
        await store.load(userID: userID)

        async let first = store.save(ProfileEdit(from: profile()))
        async let second = store.save(ProfileEdit(from: profile()))
        let results = await [first, second]

        #expect(results.contains(true))
        #expect(results.contains(false))
        #expect(await profiles.saves.count == 1)
    }

    /// Signing out must not leave one account's name on the next one's screen.
    @Test
    func signingOutForgetsTheProfile() async {
        let store = ProfileStore(profiles: StubProfiles(profile: profile()))
        await store.load(userID: userID)

        store.clear()

        #expect(store.state == .loading)
        #expect(store.saveFailure == nil)
    }

    // MARK: - Counts

    @Test
    func theCountsArriveWithTheProfile() async {
        let counts = ProfileCounts(friends: 5, followers: 12, following: 8)
        let store = ProfileStore(profiles: StubProfiles(profile: profile(), counts: counts))

        await store.load(userID: userID)

        #expect(store.counts == counts)
    }

    /// An edit returns only the profile. Dropping the counts with it would
    /// blank them every time someone changed their bio.
    @Test
    func savingKeepsTheCounts() async {
        let counts = ProfileCounts(friends: 5, followers: 12, following: 8)
        let profiles = StubProfiles(
            profile: profile(),
            counts: counts,
            acknowledging: profile(bio: "New bio")
        )
        let store = ProfileStore(profiles: profiles)
        await store.load(userID: userID)

        _ = await store.save(ProfileEdit(from: profile(bio: "New bio")))

        #expect(store.counts == counts)
    }

    @Test
    func signingOutForgetsTheCounts() async {
        let counts = ProfileCounts(friends: 5, followers: 12, following: 8)
        let store = ProfileStore(profiles: StubProfiles(profile: profile(), counts: counts))
        await store.load(userID: userID)

        store.clear()

        #expect(store.counts == nil)
    }

    // MARK: - Watchlist visibility

    /// The reason it does not wait for the server: the control has to answer
    /// the tap, not the round trip.
    @Test
    func choosingAVisibilityShowsItBeforeTheServerIsTold() async {
        let profiles = StubProfiles(profile: profile())
        let store = ProfileStore(profiles: profiles, visibilityDelay: .milliseconds(20))
        await store.load(userID: userID)

        store.setWatchlistVisibility(.public)

        #expect(store.state.profile?.watchlistVisibility == .public)
        #expect(await profiles.saves.isEmpty)
    }

    /// A burst of taps is one request, for whatever was settled on.
    @Test
    func abusrtOfTapsSendsOnlyTheLastChoice() async throws {
        let profiles = StubProfiles(profile: profile())
        let store = ProfileStore(profiles: profiles, visibilityDelay: .milliseconds(20))
        await store.load(userID: userID)

        store.setWatchlistVisibility(.public)
        store.setWatchlistVisibility(.private)
        store.setWatchlistVisibility(.friends)
        store.setWatchlistVisibility(.public)
        await store.flushWatchlistVisibility()

        let saves = await profiles.saves
        #expect(saves.count == 1)
        #expect(saves.first?.watchlistVisibility == .public)
    }

    /// Choosing what is already chosen is not a change, so it sends nothing.
    @Test
    func choosingTheCurrentVisibilitySendsNothing() async {
        let profiles = StubProfiles(profile: profile())
        let store = ProfileStore(profiles: profiles, visibilityDelay: .milliseconds(20))
        await store.load(userID: userID)

        store.setWatchlistVisibility(.friends)
        await store.flushWatchlistVisibility()

        #expect(await profiles.saves.isEmpty)
    }

    /// A refusal has to put the choice back: leaving it showing would tell
    /// someone their watchlist is private when the server still has it public.
    @Test
    func arefusedVisibilityChangeGoesBackToWhatTheServerHolds() async {
        let profiles = StubProfiles(profile: profile(), failingSaves: true)
        let store = ProfileStore(profiles: profiles, visibilityDelay: .milliseconds(20))
        await store.load(userID: userID)

        store.setWatchlistVisibility(.public)
        await store.flushWatchlistVisibility()

        #expect(store.state.profile?.watchlistVisibility == .friends)
        #expect(store.saveFailure != nil)
    }

    /// Signing out must not leave a pending change to land on the next account.
    @Test
    func signingOutDropsAPendingVisibilityChange() async {
        let profiles = StubProfiles(profile: profile())
        let store = ProfileStore(profiles: profiles, visibilityDelay: .milliseconds(20))
        await store.load(userID: userID)
        store.setWatchlistVisibility(.public)

        store.clear()
        await store.flushWatchlistVisibility()

        #expect(await profiles.saves.isEmpty)
    }

    // MARK: - What the screen shows

    @Test
    func adisplayNameIsWhatItLeadsWith() {
        #expect(profile().title(fallback: "you@example.com") == "A Reader")
    }

    @Test
    func withoutADisplayNameItLeadsWithTheUsername() {
        #expect(profile(displayName: nil).title(fallback: "you@example.com") == "@reader")
    }

    /// The state the endpoint exists for: signup never asked this account for
    /// a username, so there is nothing to lead with but the account itself.
    @Test
    func withoutEitherItFallsBackToWhatEveryAccountHas() {
        let bare = profile(username: nil, displayName: nil)

        #expect(bare.title(fallback: "you@example.com") == "you@example.com")
    }
}

private actor StubProfiles: ProfileEditing {
    private(set) var loads = 0
    private(set) var saves: [ProfileEdit] = []

    private let profile: UserProfile
    private let counts: ProfileCounts
    private let acknowledging: UserProfile?
    private var failingLoads: Int
    private var failingSaves: Bool

    init(
        profile: UserProfile,
        counts: ProfileCounts = ProfileCounts(friends: 0, followers: 0, following: 0),
        acknowledging: UserProfile? = nil,
        failingLoads: Int = 0,
        failingSaves: Bool = false
    ) {
        self.profile = profile
        self.counts = counts
        self.acknowledging = acknowledging
        self.failingLoads = failingLoads
        self.failingSaves = failingSaves
    }

    func stopFailingSaves() {
        failingSaves = false
    }

    func profile(userID _: String) async throws -> ProfileOverview {
        loads += 1

        if failingLoads > 0 {
            failingLoads -= 1
            throw URLError(.notConnectedToInternet)
        }

        return ProfileOverview(profile: profile, counts: counts)
    }

    func updateProfile(_ edit: ProfileEdit) async throws -> UserProfile {
        saves.append(edit)

        if failingSaves {
            throw URLError(.notConnectedToInternet)
        }

        return acknowledging ?? profile
    }
}
