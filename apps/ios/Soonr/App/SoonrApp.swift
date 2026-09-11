import SwiftUI

@main
struct SoonrApp: App {
    private let dependencies = AppDependencies.live()

    @State private var theme = ThemeSettings()

    var body: some Scene {
        WindowGroup {
            RootTabView(dependencies: dependencies)
                .environment(theme)
                .tint(theme.accent.color)
                .preferredColorScheme(theme.appearance.colorScheme)
        }
    }
}
