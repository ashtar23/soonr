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
    /// Asked for by tapping the tab already being looked at. Carries a count
    /// so that asking twice reads as two requests rather than one.
    struct ScrollToTopRequest: Equatable {
        let tab: AppTab
        let count: Int
    }

    private(set) var selectedTab: AppTab = .home
    var notificationsPath = NavigationPath()
    private(set) var scrollToTopRequest: ScrollToTopRequest?

    /// Every tab change comes through here, including the one iOS treats
    /// specially: tapping the tab you are already on.
    ///
    /// That re-tap only ever scrolls. Popping the stack as well would be the
    /// system behaviour, but this method cannot tell a tap apart from the
    /// selection being set in code — and a push notification does exactly
    /// that, one line after putting its destination on the path. Popping here
    /// would throw that destination away and the deep link would open the list
    /// and nothing else. A scroll request costs nothing if it was not asked
    /// for; a lost destination is the bug we already fixed once.
    func select(_ tab: AppTab) {
        guard tab == selectedTab else {
            selectedTab = tab
            return
        }

        scrollToTopRequest = ScrollToTopRequest(
            tab: tab,
            count: (scrollToTopRequest?.count ?? 0) + 1
        )
    }

    func open(_ notification: OpenedPushNotification) {
        notificationsPath = NavigationPath([notification.destination])
        selectedTab = .notifications
    }

    /// Signing out leaves nothing of the previous account stacked up.
    func reset() {
        notificationsPath = NavigationPath()
        scrollToTopRequest = nil
        selectedTab = .home
    }
}
