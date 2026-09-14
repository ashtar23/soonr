import Foundation
import Testing

@testable import Soonr

@Suite
struct NotificationGameGroupTests {
    private func record(
        id: String,
        titleID: String,
        readAt: String? = nil
    ) -> NotificationRecord {
        NotificationRecord(
            id: id,
            eventType: .releaseApproaching,
            destinationTitleID: titleID,
            titleName: titleID,
            titleArtworkURL: nil,
            message: "Release approaching",
            subtitle: nil,
            payload: .releaseApproaching(targetReleaseDate: "2026-01-05"),
            createdAt: "2026-01-03T12:00:00.000Z",
            readAt: readAt
        )
    }

    @Test
    func onegameIsOneGroup() {
        let groups = NotificationGameGroup.groups(for: [
            record(id: "a", titleID: "rawg:1"),
            record(id: "b", titleID: "rawg:1"),
        ])

        #expect(groups.count == 1)
        #expect(groups.first?.records.map(\.id) == ["a", "b"])
    }

    /// A group takes the position of its newest notification, which is what
    /// keeps the list in the order the server sent it.
    @Test
    func groupsKeepTheOrderTheirNewestRowHad() {
        let groups = NotificationGameGroup.groups(for: [
            record(id: "a", titleID: "rawg:1"),
            record(id: "b", titleID: "rawg:2"),
            record(id: "c", titleID: "rawg:1"),
        ])

        #expect(groups.map(\.titleID) == ["rawg:1", "rawg:2"])
    }

    @Test
    func rowsWithinAGroupKeepTheirOrderToo() {
        let groups = NotificationGameGroup.groups(for: [
            record(id: "a", titleID: "rawg:1"),
            record(id: "b", titleID: "rawg:2"),
            record(id: "c", titleID: "rawg:1"),
        ])

        #expect(groups.first?.records.map(\.id) == ["a", "c"])
    }

    @Test
    func theLatestIsTheNewestOne() {
        let groups = NotificationGameGroup.groups(for: [
            record(id: "newest", titleID: "rawg:1"),
            record(id: "older", titleID: "rawg:1"),
        ])

        #expect(groups.first?.latest.id == "newest")
    }

    @Test
    func agameHeardFromOnceIsNotCollapsed() {
        let groups = NotificationGameGroup.groups(for: [record(id: "a", titleID: "rawg:1")])

        #expect(groups.first?.isCollapsed == false)
        #expect(groups.first?.hiddenCount == 0)
    }

    @Test
    func agameHeardFromSixTimesHidesFive() {
        let records = (0..<6).map { record(id: "a\($0)", titleID: "rawg:1") }

        let group = NotificationGameGroup.groups(for: records).first

        #expect(group?.isCollapsed == true)
        #expect(group?.hiddenCount == 5)
    }

    /// The tint has to answer for everything folded away, or a group would look
    /// read while holding something unread.
    @Test
    func agroupIsUnreadWhenAnythingInsideIs() {
        let groups = NotificationGameGroup.groups(for: [
            record(id: "a", titleID: "rawg:1", readAt: "2026-01-03T13:00:00.000Z"),
            record(id: "b", titleID: "rawg:1"),
        ])

        #expect(groups.first?.hasUnread == true)
    }

    @Test
    func agroupIsReadOnlyWhenEverythingInsideIs() {
        let read = "2026-01-03T13:00:00.000Z"
        let groups = NotificationGameGroup.groups(for: [
            record(id: "a", titleID: "rawg:1", readAt: read),
            record(id: "b", titleID: "rawg:1", readAt: read),
        ])

        #expect(groups.first?.hasUnread == false)
    }

    @Test
    func anEmptyListHasNoGroups() {
        #expect(NotificationGameGroup.groups(for: []).isEmpty)
    }

    /// Notifications are about a game, and two of them about the same game are
    /// the same group even when everything else differs.
    @Test
    func thedestinationIsWhatGathersThemRatherThanTheName() {
        let groups = NotificationGameGroup.groups(for: [
            record(id: "a", titleID: "rawg:1"),
            NotificationRecord(
                id: "b",
                eventType: .releaseDateChanged,
                destinationTitleID: "rawg:1",
                titleName: "Renamed Since",
                titleArtworkURL: nil,
                message: "Release date changed",
                subtitle: nil,
                payload: .releaseDateChanged(nextReleaseDate: "2026-03-01"),
                createdAt: "2026-01-02T12:00:00.000Z",
                readAt: nil
            ),
        ])

        #expect(groups.count == 1)
        #expect(groups.first?.records.count == 2)
    }
}
