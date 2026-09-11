import Testing

@testable import Soonr

struct AppTabTests {
    @Test
    func primaryTabsMatchTheProductNavigationContract() {
        #expect(
            AppTab.allCases == [
                .home,
                .watchlist,
                .notifications,
                .search,
                .account,
            ]
        )
    }

    @Test(arguments: AppTab.allCases)
    func everyTabHasVisibleMetadata(tab: AppTab) {
        #expect(tab.title.isEmpty == false)
        #expect(tab.systemImage.isEmpty == false)
    }
}
