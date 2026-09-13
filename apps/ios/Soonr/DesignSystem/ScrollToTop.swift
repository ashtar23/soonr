import SwiftUI

/// Takes a scrollable tab back to its top when its tab is tapped again.
///
/// iOS does this by itself, but only by animating towards an offset it has to
/// estimate: rows in a `List` are laid out lazily, so their real heights
/// replace the estimates while the animation is still running and it stops
/// short. A long list then takes several taps. Scrolling to a known view
/// instead does not depend on any height being known in advance.
///
/// The anchor is a view of its own, above the rows, because the identifier is
/// what makes it findable — and an identifier on the rows themselves would
/// make `List` build every one of them eagerly rather than as they are needed,
/// which on a paged list is the whole cost of paging paid at once.
struct ScrollToTop<Content: View>: View {
    /// Which tab's taps to answer, so a request meant for one list does not
    /// move another that is also on screen.
    let tab: AppTab

    @ViewBuilder var content: () -> Content

    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollViewReader { proxy in
            content()
                .onChange(of: router.scrollToTopRequest) { _, request in
                    guard request?.tab == tab else {
                        return
                    }

                    withAnimation {
                        proxy.scrollTo(ScrollToTopAnchor.id, anchor: .top)
                    }
                }
        }
    }
}

/// The view to scroll to. Put it above the rows, outside any `ForEach`.
struct ScrollToTopAnchor: View {
    static let id = "scroll-to-top-anchor"

    var body: some View {
        Color.clear
            .frame(height: 0)
            .id(Self.id)
            .listRowSeparator(.hidden)
            // Zero height still reserves a row's padding otherwise, which
            // shows as a gap above the first row.
            .listRowInsets(EdgeInsets())
            .accessibilityHidden(true)
    }
}
