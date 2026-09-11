import Foundation
import Testing

@testable import Soonr

struct ReleaseDateTextTests {
    private let locale = Locale(identifier: "en_US")

    @Test(arguments: [
        ("2025-09-25", TitleRelease.Precision.day, "Sep 25, 2025"),
        ("2025-01-01", .day, "Jan 1, 2025"),
        ("2025-09-25", .month, "September 2025"),
        ("2025-09", .month, "September 2025"),
        ("2025-09-25", .year, "2025"),
        ("2025", .year, "2025"),
        ("2025-09-25", .unknown, "TBA"),
    ])
    func formatsAtTheReportedPrecision(
        isoDate: String,
        precision: TitleRelease.Precision,
        expected: String
    ) {
        #expect(ReleaseDateText.format(isoDate, precision: precision, locale: locale) == expected)
    }

    @Test(
        arguments: [nil, "", "soon", "2025-13-01", "2025-02-30", "25-09-25", "2025-09-25-01"]
            as [String?])
    func missingOrMalformedDatesAreUnannounced(isoDate: String?) {
        #expect(ReleaseDateText.format(isoDate, precision: .day, locale: locale) == "TBA")
    }

    @Test(arguments: [
        ("2026-09-11", 0),
        ("2026-09-12", 1),
        ("2026-09-15", 4),
        ("2026-09-10", -1),
        ("2027-09-11", 365),
    ])
    func daysUntilCountsCalendarDays(isoDate: String, expected: Int) throws {
        let now = try Date("2026-09-11T20:00:00Z", strategy: .iso8601)
        let utc = try #require(TimeZone(identifier: "UTC"))

        #expect(ReleaseDateText.daysUntil(isoDate, now: now, timeZone: utc) == expected)
    }

    @Test
    func daysUntilUsesTheViewersLocalDate() throws {
        // 03:00 UTC on Sep 12 is still the evening of Sep 11 in Los Angeles.
        let now = try Date("2026-09-12T03:00:00Z", strategy: .iso8601)
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let utc = try #require(TimeZone(identifier: "UTC"))

        #expect(ReleaseDateText.daysUntil("2026-09-12", now: now, timeZone: losAngeles) == 1)
        #expect(ReleaseDateText.daysUntil("2026-09-12", now: now, timeZone: utc) == 0)
    }

    @Test(arguments: [nil, "soon", "2026-02-30"] as [String?])
    func daysUntilIsNilForMissingOrMalformedDates(isoDate: String?) {
        #expect(ReleaseDateText.daysUntil(isoDate) == nil)
    }

    @Test(
        arguments: [
            (-1, nil),
            (0, "Out today"),
            (1, "Tomorrow"),
            (4, "In 4 days"),
            (30, "In 30 days"),
            (31, "Upcoming"),
        ] as [(Int, String?)])
    func countdownDescribesUpcomingReleases(days: Int, expected: String?) {
        #expect(ReleaseDateText.countdown(daysUntil: days) == expected)
    }
}
