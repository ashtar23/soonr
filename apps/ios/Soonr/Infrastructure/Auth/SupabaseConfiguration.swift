import Foundation

/// Public Supabase settings: the project URL and its publishable key. Secret
/// and service-role keys never reach the app bundle.
struct SupabaseConfiguration: Equatable, Sendable {
    let url: URL
    let publishableKey: String
}
