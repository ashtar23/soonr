import Foundation
import Testing

@testable import Soonr

struct AppConfigurationTests {
    @Test
    func theRunningAppHasAUsableAPIBaseURL() throws {
        let configured = Bundle.main.object(
            forInfoDictionaryKey: AppConfiguration.InfoKey.apiBaseURL)

        let value = try #require(configured as? String)
        #expect(AppConfiguration.apiBaseURL(value) != nil)
    }

    @Test(arguments: [
        "https://soonr-staging.up.railway.app",
        "http://127.0.0.1:3001",
        "https://api.soonr.app/",
    ])
    func absoluteHTTPURLsAreAccepted(value: String) {
        #expect(AppConfiguration.apiBaseURL(value) != nil)
    }

    @Test(
        arguments: [
            nil,
            "",
            "   ",
            // An unset SOONR_API_HOST leaves the scheme with no host behind it.
            "https://",
            "soonr-staging.up.railway.app",
            "ftp://soonr-staging.up.railway.app",
        ] as [String?])
    func unusableValuesAreRejected(value: String?) {
        #expect(AppConfiguration.apiBaseURL(value) == nil)
    }
}
