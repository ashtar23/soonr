import Foundation
import Observation

/// Where a tapped push should take the viewer.
///
/// The tab has to change and the stack has to push, and those are owned by
/// two different views, so both read this rather than one reaching into the
/// other.
@MainActor
@Observable
final class PushRoutingStore {
    private(set) var pendingDestination: TitleDestination?

    func open(_ notification: OpenedPushNotification) {
        pendingDestination = notification.destination
    }

    /// Cleared once the stack has pushed it, so returning to the tab later
    /// does not push it a second time.
    func destinationOpened() {
        pendingDestination = nil
    }
}
