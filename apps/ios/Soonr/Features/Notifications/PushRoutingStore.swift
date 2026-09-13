import Foundation
import Observation

/// Where a tapped push takes the viewer.
///
/// The tab and the destination are set together rather than one being derived
/// from the other: the notifications tab is built the first time it is
/// selected, so a screen reacting to a change would be created after that
/// change had already happened and would never see it.
@MainActor
@Observable
final class PushRoutingStore {
    var selectedTab: AppTab = .home
    private(set) var pendingDestination: TitleDestination?

    func open(_ notification: OpenedPushNotification) {
        pendingDestination = notification.destination
        selectedTab = .notifications
    }

    /// Cleared once the stack has pushed it, so returning to the tab later
    /// does not push it a second time.
    func destinationOpened() {
        pendingDestination = nil
    }
}
