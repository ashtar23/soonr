import Foundation

/// Secret and service-role keys never reach the app bundle.
struct SupabaseConfiguration: Equatable, Sendable {
    let url: URL
    let publishableKey: String
}
