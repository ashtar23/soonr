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

    @Test(arguments: [nil, "", "soon", "2025-13-01", "2025-02-30", "25-09-25", "2025-09-25-01"] as [String?])
    func missingOrMalformedDatesAreUnannounced(isoDate: String?) {
        #expect(ReleaseDateText.format(isoDate, precision: .day, locale: locale) == "TBA")
    }
}
