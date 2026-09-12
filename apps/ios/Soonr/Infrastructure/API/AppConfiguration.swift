import Foundation

struct AppConfiguration: Sendable {
    /// Info.plist keys filled in by the per-configuration xcconfig files.
    enum InfoKey {
        static let apiBaseURL = "SoonrAPIBaseURL"
    }

    let apiBaseURL: URL
    let supabasePublishableKey: String?

    static let live = AppConfiguration(
        apiBaseURL: resolvedAPIBaseURL(),
        supabasePublishableKey: nonEmptyEnvironmentValue(named: "SOONR_SUPABASE_PUBLISHABLE_KEY")
    )

    private static func resolvedAPIBaseURL() -> URL {
        let configured = Bundle.main.object(forInfoDictionaryKey: InfoKey.apiBaseURL) as? String

        #if DEBUG
            // Debug builds keep the scheme environment override for pointing at
            // a local API.
            let override = nonEmptyEnvironmentValue(named: "SOONR_API_BASE_URL")
            if let url = Self.apiBaseURL(override) {
                return url
            }
        #endif

        guard let url = apiBaseURL(configured) else {
            // A build that reaches here has no usable backend, which must be
            // obvious rather than a silent fallback to staging.
            preconditionFailure(
                """
                \(InfoKey.apiBaseURL) is missing or invalid: \(configured ?? "nil").
                Set SOONR_API_HOST in the configuration's xcconfig file.
                """
            )
        }

        return url
    }

    /// Accepts only absolute http(s) URLs with a host, so an unset
    /// `SOONR_API_HOST` resolving to "https://" is rejected.
    static func apiBaseURL(_ value: String?) -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            value.isEmpty == false,
            let url = URL(string: value),
            let scheme = url.scheme,
            ["http", "https"].contains(scheme),
            let host = url.host(),
            host.isEmpty == false
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
