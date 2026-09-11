import Foundation

struct AppConfiguration: Sendable {
    let apiBaseURL: URL
    let supabasePublishableKey: String?

    static let live = AppConfiguration(
        apiBaseURL: environmentURL
            ?? URL(string: "https://soonr-staging.up.railway.app")!,
        supabasePublishableKey: nonEmptyEnvironmentValue(
            named: "SOONR_SUPABASE_PUBLISHABLE_KEY"
        )
    )

    private static var environmentURL: URL? {
        guard let value = nonEmptyEnvironmentValue(named: "SOONR_API_BASE_URL"),
            let url = URL(string: value),
            let scheme = url.scheme,
            ["http", "https"].contains(scheme)
        else {
            return nil
        }

        return url
    }

    private static func nonEmptyEnvironmentValue(named name: String) -> String? {
        guard
            let value = ProcessInfo.processInfo.environment[name]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            value.isEmpty == false
        else {
            return nil
        }

        return value
    }
}
