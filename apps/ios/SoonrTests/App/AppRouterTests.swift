import Foundation
import Testing

@testable import Soonr

@MainActor
struct AppRouterTests {
    private let opened = OpenedPushNotification(
        notificationID: "notification-1",
        destination: TitleDestination(id: "rawg:662318", name: "Marvel's Wolverine")
    )

    /// Both at once, from one place: a tab derived from the destination by a
    /// second screen is what made this miss the first time.
    @Test
    func openingAPushSelectsTheTabAndStacksTheGame() {
        let router = AppRouter()

        router.open(opened)

        #expect(router.selectedTab == .notifications)
        #expect(router.notificationsPath.count == 1)
    }

    /// The screen is built when its tab is first selected, so the path has to
    /// be readable then rather than delivered to it at the moment it changes.
    @Test
    func theDestinationSurvivesUntilSomethingRendersIt() {
        let router = AppRouter()

        router.open(opened)
        // Whatever else happens before the notifications screen exists.
        router.selectedTab = .notifications

        #expect(router.notificationsPath.count == 1)
    }

    @Test
    func asecondPushReplacesTheFirstRatherThanStackingOnIt() {
        let router = AppRouter()

        router.open(opened)
        router.open(
            OpenedPushNotification(
                notificationID: "notification-2",
                destination: TitleDestination(id: "rawg:3498", name: "Grand Theft Auto VI")
            )
        )

        #expect(router.notificationsPath.count == 1)
    }

    @Test
    func signingOutLeavesNothingOfThePreviousAccountStacked() {
        let router = AppRouter()
        router.open(opened)

        router.reset()

        #expect(router.notificationsPath.isEmpty)
        #expect(router.selectedTab == .home)
    }
}
