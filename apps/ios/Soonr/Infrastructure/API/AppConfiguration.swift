import Foundation

struct AppConfiguration: Sendable {
    /// Info.plist keys filled in by the per-configuration xcconfig files.
    enum InfoKey {
        static let apiBaseURL = "SoonrAPIBaseURL"
        static let supabaseURL = "SoonrSupabaseURL"
        static let supabasePublishableKey = "SoonrSupabasePublishableKey"
    }

    let apiBaseURL: URL
    let supabase: SupabaseConfiguration?

    var supabasePublishableKey: String? {
        supabase?.publishableKey
    }

    static let live = AppConfiguration(
        apiBaseURL: resolvedAPIBaseURL(),
        supabase: resolvedSupabase()
    )

    /// `nil` when Local.xcconfig has not supplied a key, which is the case on
    /// a fresh clone and in CI; features that need a session say so rather than
    /// failing at launch.
    private static func resolvedSupabase() -> SupabaseConfiguration? {
        let url = Bundle.main.object(forInfoDictionaryKey: InfoKey.supabaseURL) as? String
        let key =
            nonEmptyEnvironmentValue(named: "SOONR_SUPABASE_PUBLISHABLE_KEY")
            ?? (Bundle.main.object(forInfoDictionaryKey: InfoKey.supabasePublishableKey) as? String)

        return supabaseConfiguration(url: url, publishableKey: key)
    }

    static func supabaseConfiguration(url: String?, publishableKey: String?)
        -> SupabaseConfiguration?
    {
        guard let url = apiBaseURL(url),
            let key = publishableKey?.trimmingCharacters(in: .whitespacesAndNewlines),
            key.isEmpty == false
        else {
            return nil
        }

        return SupabaseConfiguration(url: url, publishableKey: key)
    }

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
