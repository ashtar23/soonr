import SwiftUI

@main
struct SoonrApp: App {
    private let dependencies: AppDependencies

    @State private var theme = ThemeSettings()
    @State private var session: SessionStore

    init() {
        let dependencies = AppDependencies.live()
        self.dependencies = dependencies
        _session = State(initialValue: SessionStore(authentication: dependencies.authentication))
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
