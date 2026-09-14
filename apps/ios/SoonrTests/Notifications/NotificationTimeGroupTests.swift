import Foundation
import Testing

@testable import Soonr

/// Fixed to UTC so a grouping that depends on calendar days is not decided by
/// where the test happens to run.
@Suite
struct NotificationTimeGroupTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let now = Date(timeIntervalSince1970: 1_767_268_800)  // 2026-01-01 12:00 UTC

    private func group(_ timestamp: String) -> NotificationTimeGroup {
        NotificationTimeGroup.of(timestamp, now: now, calendar: calendar)
    }

    @Test
    func thisMorningIsToday() {
        #expect(group("2026-01-01T08:00:00.000Z") == .today)
    }

    /// Calendar days, not elapsed hours: something from late last night is only
    /// a few hours old and still belongs under yesterday.
    @Test
    func lateLastNightIsNotToday() {
        #expect(group("2025-12-31T23:30:00.000Z") == .thisWeek)
    }

    @Test
    func laterTodayIsStillToday() {
        #expect(group("2026-01-01T23:00:00.000Z") == .today)
    }

    @Test
    func threeDaysAgoIsThisWeek() {
        #expect(group("2025-12-29T12:00:00.000Z") == .thisWeek)
    }

    @Test
    func aMonthAgoIsEarlier() {
        #expect(group("2025-12-01T12:00:00.000Z") == .earlier)
    }

    /// The boundary, which is the part worth pinning down.
    @Test
    func justInsideAWeekIsThisWeekAndJustOutsideIsEarlier() {
        #expect(group("2025-12-25T12:00:01.000Z") == .thisWeek)
        #expect(group("2025-12-25T11:59:59.000Z") == .earlier)
    }

    /// Undatable rather than old, and the last group is the one that makes no
    /// claim about when.
    @Test
    func atimestampThatCannotBeReadIsEarlier() {
        #expect(group("not a date") == .earlier)
    }

    @Test
    func atimestampWithoutFractionalSecondsIsStillRead() {
        #expect(group("2026-01-01T08:00:00Z") == .today)
    }

    // MARK: - Sections

    private func sections(_ timestamps: [String]) -> [NotificationSection] {
        NotificationTimeGroup.sections(
            for: timestamps.enumerated().map { index, timestamp in
                record(id: "notification-\(index)", createdAt: timestamp)
            },
            now: now,
            calendar: calendar
        )
    }

    private func record(id: String, createdAt: String) -> NotificationRecord {
        NotificationRecord(
            id: id,
            eventType: .releaseApproaching,
            destinationTitleID: "rawg:1",
            titleName: "Hades II",
            titleArtworkURL: nil,
            message: "Release approaching",
            subtitle: nil,
            payload: .releaseApproaching(targetReleaseDate: "2026-01-05"),
            createdAt: createdAt,
            readAt: nil
        )
    }

    @Test
    func rowsAreGatheredUnderTheirOwnHeading() {
        let result = sections([
            "2026-01-01T09:00:00.000Z",
            "2026-01-01T08:00:00.000Z",
            "2025-12-29T12:00:00.000Z",
            "2025-11-01T12:00:00.000Z",
        ])

        #expect(result.map(\.group) == [.today, .thisWeek, .earlier])
        #expect(result.first?.records.count == 2)
    }

    /// The server sends newest first, and grouping must not reorder anything.
    @Test
    func theOrderTheServerSentIsKept() {
        let result = sections([
            "2026-01-01T09:00:00.000Z",
            "2026-01-01T08:00:00.000Z",
        ])

        #expect(result.first?.records.map(\.id) == ["notification-0", "notification-1"])
    }

    @Test
    func anEmptyListHasNoHeadings() {
        #expect(sections([]).isEmpty)
    }

    @Test
    func asingleGroupIsOneSection() {
        let result = sections(["2026-01-01T09:00:00.000Z", "2026-01-01T08:00:00.000Z"])

        #expect(result.count == 1)
    }

    /// Paging appends older rows, so a heading appears rather than an existing
    /// one being split in two.
    @Test
    func alaterPageExtendsTheLastHeadingRatherThanRepeatingIt() {
        let result = sections([
            "2026-01-01T09:00:00.000Z",
            "2025-12-29T12:00:00.000Z",
            "2025-12-28T12:00:00.000Z",
        ])

        #expect(result.map(\.group) == [.today, .thisWeek])
        #expect(result.last?.records.count == 2)
    }
}
