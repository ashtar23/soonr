import Foundation

enum PushAuthorization: Sendable {
    /// Never asked. The prompt is still available.
    case undetermined
    case authorized
    /// Asked and refused. iOS will not ask again, so the only way back is
    /// Settings.
    case denied
}

/// The system side of push, behind a protocol so the store that decides when
/// to ask can be tested without a device.
protocol PushAuthorizing: Sendable {
    func authorization() async -> PushAuthorization
    /// Shows the system prompt, once ever. Returns what the viewer chose.
    func requestAuthorization() async -> Bool
    /// Asks APNs for a token, which arrives through `PushDeviceTokens`.
    func registerForRemoteNotifications() async
    /// The number on the app icon, which iOS keeps showing until it is told
    /// otherwise — a push sets it, and nothing clears it by itself.
    func setBadgeCount(_ count: Int) async
}
