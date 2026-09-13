import Foundation
import Testing

@testable import Soonr

struct NotificationTimestampTests {
    private let locale = Locale(identifier: "en_US")
    private let now = Date(timeIntervalSince1970: 1_767_441_600)  // 2026-01-03T12:00:00Z

    private func text(_ timestamp: String) -> String? {
        NotificationTimestamp.text(timestamp, now: now, locale: locale)
    }

    @Test
    func aJustArrivedNotificationDoesNotReadAsZeroSecondsAgo() {
        #expect(text("2026-01-03T11:59:30.000Z") == "Just now")
    }

    @Test(arguments: [
        ("2026-01-03T10:00:00.000Z", "2 hours ago"),
        ("2026-01-02T12:00:00.000Z", "yesterday"),
        ("2025-12-31T12:00:00.000Z", "3 days ago"),
    ])
    func recentArrivalsReadAsAnAge(timestamp: String, expected: String) {
        #expect(text(timestamp) == expected)
    }

    /// Past a week the age stops being easier to picture than the day itself.
    @Test
    func olderArrivalsReadAsADate() {
        #expect(text("2025-12-20T12:00:00.000Z") == "Dec 20, 2025")
    }

    @Test
    func aTimestampWithoutFractionalSecondsStillParses() {
        #expect(text("2025-12-20T12:00:00Z") == "Dec 20, 2025")
    }

    @Test(arguments: ["", "yesterday", "2026-01-03", "not a date"])
    func anUnreadableTimestampIsLeftOut(timestamp: String) {
        #expect(text(timestamp) == nil)
    }
}
