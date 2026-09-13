import Foundation
import Testing

@testable import Soonr

struct NotificationCaptionTests {
    private let locale = Locale(identifier: "en_US")
    private let now = Date(timeIntervalSince1970: 1_767_441_600)  // 2026-01-03T12:00:00Z

    private func caption(_ record: NotificationRecord) -> String? {
        NotificationCaption.text(for: record, now: now, locale: locale)
    }

    @Test(arguments: [
        ("2026-01-03", "Out today"),
        ("2026-01-04", "Out tomorrow"),
        ("2026-01-10", "In 7 days"),
        ("2026-02-02", "In 30 days"),
        ("2026-11-19", "Nov 19, 2026"),
    ])
    func aReleaseIsDescribedFromTodayNotFromTheDayItWasGenerated(
        releaseDate: String,
        expected: String
    ) {
        #expect(caption(.approaching(releaseDate)) == expected)
    }

    /// The reason this exists: the server froze "Releases today" into the row
    /// on the release date, and it stayed there.
    @Test
    func aStaleSentenceFromTheServerIsNotUsed() {
        let record = NotificationRecord(
            .releaseApproaching(targetReleaseDate: "2025-12-20"),
            subtitle: "Releases today"
        )

        #expect(caption(record) == "Out now")
    }

    @Test
    func aDateChangeNamesTheNewDate() {
        #expect(caption(.dateChanged("2026-11-19")) == "Moved to Nov 19, 2026")
    }

    @Test
    func aPayloadWithNoDateFallsBackToWhatTheServerWrote() {
        let record = NotificationRecord(
            .releaseApproaching(targetReleaseDate: nil),
            subtitle: "Releases soon"
        )

        #expect(caption(record) == "Releases soon")
    }

    @Test
    func anUnrecognizedPayloadWithNoSubtitleFallsBackToTheMessage() {
        let record = NotificationRecord(.unrecognized, subtitle: nil)

        #expect(caption(record) == "Release approaching")
    }

    @Test
    func anUnknownPayloadShapeDecodesWithoutFailingTheRow() throws {
        let json = Data(#"{"somethingNew":"value"}"#.utf8)

        let payload = try JSONDecoder().decode(NotificationPayload.self, from: json)

        #expect(payload == .unrecognized)
    }

    @Test
    func aPayloadIsTakenFromItsKeysRatherThanTheEventType() throws {
        let json = Data(#"{"targetReleaseDate":"2026-11-19","timingPreset":"on_day"}"#.utf8)

        let payload = try JSONDecoder().decode(NotificationPayload.self, from: json)

        #expect(payload == .releaseApproaching(targetReleaseDate: "2026-11-19"))
    }
}

private extension NotificationRecord {
    static func approaching(_ date: String?) -> NotificationRecord {
        NotificationRecord(.releaseApproaching(targetReleaseDate: date), subtitle: nil)
    }

    static func dateChanged(_ date: String?) -> NotificationRecord {
        NotificationRecord(.releaseDateChanged(nextReleaseDate: date), subtitle: nil)
    }

    init(_ payload: NotificationPayload, subtitle: String?) {
        self.init(
            id: "notification-1",
            eventType: .releaseApproaching,
            destinationTitleID: "rawg:3498",
            titleName: "Grand Theft Auto VI",
            titleArtworkURL: nil,
            message: "Release approaching",
            subtitle: subtitle,
            payload: payload,
            createdAt: "2026-01-03T10:00:00.000Z",
            readAt: nil
        )
    }
}
