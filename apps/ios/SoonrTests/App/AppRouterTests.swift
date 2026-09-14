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
        router.select(.notifications)

        #expect(router.notificationsPath.count == 1)
    }

    // MARK: - Tapping the tab already showing

    @Test
    func tappingAnotherTabJustChangesTabs() {
        let router = AppRouter()

        router.select(.notifications)

        #expect(router.selectedTab == .notifications)
        #expect(router.scrollToTopRequest == nil)
    }

    @Test
    func tappingTheTabAlreadyShowingAsksItToScrollToTheTop() {
        let router = AppRouter()
        router.select(.notifications)

        router.select(.notifications)

        #expect(router.scrollToTopRequest?.tab == .notifications)
    }

    /// Asking twice has to read as two requests, or the second tap would look
    /// identical to the first and change nothing.
    @Test
    func askingTwiceReadsAsTwoRequests() {
        let router = AppRouter()
        router.select(.notifications)

        router.select(.notifications)
        let first = router.scrollToTopRequest
        router.select(.notifications)

        #expect(router.scrollToTopRequest != first)
    }

    /// A push sets the destination and then the tab, and selecting a tab
    /// cannot tell that apart from a tap. Anything that discarded the path
    /// here would open the list and nothing else — the deep link bug again.
    @Test
    func selectingTheTabAPushJustOpenedKeepsItsDestination() {
        let router = AppRouter()
        router.open(opened)

        router.select(.notifications)

        #expect(router.notificationsPath.count == 1)
    }

    @Test
    func signingOutForgetsAPendingRequest() {
        let router = AppRouter()
        router.select(.home)

        router.reset()

        #expect(router.scrollToTopRequest == nil)
        #expect(router.selectedTab == .home)
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
