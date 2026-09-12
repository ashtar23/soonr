import SwiftUI

@main
struct SoonrApp: App {
    private let dependencies = AppDependencies.live()

    @State private var theme = ThemeSettings()
    @State private var session: SessionStore

    init() {
        _session = State(
            initialValue: SessionStore(authentication: AppDependencies.liveAuthentication()))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(dependencies: dependencies)
                .environment(theme)
                .environment(session)
                .tint(theme.accent.color)
                .preferredColorScheme(theme.appearance.colorScheme)
                .task {
                    await session.restore()
                }
        }
    }
}
