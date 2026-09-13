import Foundation
import Observation
import SwiftUI

/// Which tab is showing and what is stacked on it.
///
/// The navigation path lives here rather than in the screen so that opening
/// something from outside — a tapped push — is a plain state change. A screen
/// that is built the first time its tab is selected simply renders the path it
/// finds, with nothing to hand over and no moment it can be too late for.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var notificationsPath = NavigationPath()

    func open(_ notification: OpenedPushNotification) {
        notificationsPath = NavigationPath([notification.destination])
        selectedTab = .notifications
    }

    /// Signing out leaves nothing of the previous account stacked up.
    func reset() {
        notificationsPath = NavigationPath()
        selectedTab = .home
    }
}
