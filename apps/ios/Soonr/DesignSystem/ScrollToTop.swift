import SwiftUI

/// Takes a scrollable tab back to its top when its tab is tapped again.
///
/// iOS does this by itself, but only by animating towards an offset it has to
/// estimate: rows in a `List` are laid out lazily, so their real heights
/// replace the estimates while the animation is still running and it stops
/// short. A long list then takes several taps. Scrolling to a known row
/// instead does not depend on any height being known in advance.
///
/// The target is the first row's own identity. `ForEach` already gives each
/// row one, so nothing has to be added to the list to make it findable — and
/// nothing should be: an `.id()` modifier on a row makes `List` build every
/// row eagerly rather than as they are needed, which on a paged list is the
/// whole cost of paging paid at once.
struct ScrollToTop<ID: Hashable, Content: View>: View {
    /// Which tab's taps to answer, so a request meant for one list does not
    /// move another that is also on screen.
    let tab: AppTab
    /// The first row, or `nil` while there are no rows to scroll to.
    let topID: ID?

    @ViewBuilder var content: () -> Content

    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollViewReader { proxy in
            content()
                .onChange(of: router.scrollToTopRequest) { _, request in
                    guard request?.tab == tab, let topID else {
                        return
                    }

                    withAnimation {
                        proxy.scrollTo(topID, anchor: .top)
                    }
                }
        }
    }
}
