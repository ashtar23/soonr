import Foundation
import Testing

@testable import Soonr

@MainActor
@Suite(.tags(.networking))
struct NotificationGameStoreTests {
    private let titleID = "rawg:1"

    private func record(
        id: String,
        titleID: String = "rawg:1",
        readAt: String? = nil
    ) -> NotificationRecord {
        NotificationRecord(
            id: id,
            eventType: .releaseApproaching,
            destinationTitleID: titleID,
            titleName: "Hades II",
            titleArtworkURL: nil,
            message: "Release approaching",
            subtitle: nil,
            payload: .releaseApproaching(targetReleaseDate: "2026-01-05"),
            createdAt: "2026-01-03T12:00:00.000Z",
            readAt: readAt
        )
    }

    private func stores(
        showing shown: [NotificationRecord],
        answering answer: [NotificationRecord],
        failing: Bool = false
    ) -> (NotificationGameStore, StubGameNotifications) {
        let service = StubGameNotifications(answer: answer, failing: failing)
        let list = NotificationsStore(notifications: service)
        return (
            NotificationGameStore(titleID: titleID, showing: shown, in: list),
            service
        )
    }

    /// There is something to read before the server answers, because the list
    /// already had some of it.
    @Test
    func itOpensOnWhatTheListAlreadyHeld() {
        let (store, _) = stores(showing: [record(id: "a")], answering: [])

        #expect(store.records.map(\.id) == ["a"])
    }

    /// The point of asking: a group counts what was paged in, and what was
    /// paged in is not all of it.
    @Test
    func theServersAnswerReplacesWhatWasPagedIn() async {
        let (store, service) = stores(
            showing: [record(id: "a")],
            answering: [record(id: "a"), record(id: "b"), record(id: "c")]
        )

        await store.load()

        #expect(store.records.map(\.id) == ["a", "b", "c"])
        #expect(await service.aboutAsked == [titleID])
    }

    /// Read elsewhere and cleared is a real answer, not a failed one.
    @Test
    func anEmptyAnswerIsShownRatherThanTreatedAsAFailure() async {
        let (store, _) = stores(showing: [record(id: "a")], answering: [])

        await store.load()

        #expect(store.records.isEmpty)
        #expect(store.loadFailed == false)
    }

    /// The rows already on screen are still worth reading.
    @Test
    func afailedLoadKeepsWhatWasAlreadyShowing() async {
        let (store, _) = stores(
            showing: [record(id: "a")],
            answering: [],
            failing: true
        )

        await store.load()

        #expect(store.records.map(\.id) == ["a"])
        #expect(store.loadFailed)
    }

    @Test
    func asecondLoadClearsAnEarlierFailure() async {
        let service = StubGameNotifications(answer: [record(id: "a")], failing: true)
        let list = NotificationsStore(notifications: service)
        let store = NotificationGameStore(titleID: titleID, showing: [], in: list)
        await store.load()
        #expect(store.loadFailed)

        await service.stopFailing()
        await store.load()

        #expect(store.loadFailed == false)
        #expect(store.records.map(\.id) == ["a"])
    }

    // MARK: - Reading

    /// The row, the collapsed row it sits under, and the badge are three views
    /// of one fact, so they move together or not at all.
    @Test
    func readingOneMovesTheListBehindItToo() async {
        let unread = record(id: "a")
        let service = StubGameNotifications(answer: [unread])
        let list = NotificationsStore(notifications: service)
        await list.load()
        let store = NotificationGameStore(titleID: titleID, showing: [unread], in: list)

        await store.markRead(id: "a")

        #expect(store.records.first?.isRead == true)
        #expect(list.state.records?.first?.isRead == true)
        #expect(await service.readIDs == ["a"])
    }

    @Test
    func readingSomethingAlreadyReadAsksForNothing() async {
        let read = record(id: "a", readAt: "2026-01-03T13:00:00.000Z")
        let service = StubGameNotifications(answer: [read])
        let list = NotificationsStore(notifications: service)
        let store = NotificationGameStore(titleID: titleID, showing: [read], in: list)

        await store.markRead(id: "a")

        #expect(await service.readIDs.isEmpty)
    }

    @Test
    func readingSomethingNotHeldAsksForNothing() async {
        let service = StubGameNotifications(answer: [])
        let list = NotificationsStore(notifications: service)
        let store = NotificationGameStore(titleID: titleID, showing: [], in: list)

        await store.markRead(id: "missing")

        #expect(await service.readIDs.isEmpty)
    }
}

private actor StubGameNotifications: NotificationsReading {
    private(set) var aboutAsked: [String] = []
    private(set) var readIDs: [String] = []

    private let answer: [NotificationRecord]
    private var failing: Bool

    init(answer: [NotificationRecord], failing: Bool = false) {
        self.answer = answer
        self.failing = failing
    }

    func stopFailing() {
        failing = false
    }

    func notifications(about titleID: String) async throws -> [NotificationRecord] {
        aboutAsked.append(titleID)

        if failing {
            throw URLError(.notConnectedToInternet)
        }

        return answer
    }

    func notifications(
        after _: String?,
        unreadOnly _: Bool
    ) async throws -> Page<NotificationRecord> {
        Page(items: answer)
    }

    func unreadNotificationCount() async throws -> Int {
        answer.count { $0.isRead == false }
    }

    func markNotificationRead(id: String) async throws -> NotificationRecord {
        readIDs.append(id)
        let record = answer.first { $0.id == id }
        return NotificationRecord(
            record ?? answer[0],
            readAt: "2026-01-03T13:00:00.000Z"
        )
    }

    func markAllNotificationsRead() async throws -> Int { 0 }
}
