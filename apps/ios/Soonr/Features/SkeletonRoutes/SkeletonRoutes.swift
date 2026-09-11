import SwiftUI

struct SignInView: View {
    var body: some View {
        PlaceholderScreen(
            icon: "person.badge.key",
            title: "Sign in",
            description: "Email and password authentication will be added in the auth slice."
        )
        .navigationTitle("Sign in")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SignUpView: View {
    var body: some View {
        PlaceholderScreen(
            icon: "person.badge.plus",
            title: "Create your account",
            description: "Account and profile setup will be added in the auth slice."
        )
        .navigationTitle("Create account")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsView: View {
    var body: some View {
        List {
            Section("Preferences") {
                NavigationLink {
                    SettingsPlaceholderView(
                        title: "General",
                        icon: "slider.horizontal.3"
                    )
                } label: {
                    Label("General", systemImage: "slider.horizontal.3")
                }

                NavigationLink {
                    SettingsPlaceholderView(title: "Watchlist", icon: "bookmark")
                } label: {
                    Label("Watchlist", systemImage: "bookmark")
                }

                NavigationLink {
                    SettingsPlaceholderView(title: "Notifications", icon: "bell")
                } label: {
                    Label("Notifications", systemImage: "bell")
                }

                NavigationLink {
                    SettingsPlaceholderView(title: "Theme", icon: "circle.lefthalf.filled")
                } label: {
                    Label("Theme", systemImage: "circle.lefthalf.filled")
                }
            }

            Section("Development") {
                NavigationLink {
                    SettingsPlaceholderView(title: "Developer", icon: "hammer")
                } label: {
                    Label("Developer", systemImage: "hammer")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsPlaceholderView: View {
    let title: String
    let icon: String

    var body: some View {
        PlaceholderScreen(
            icon: icon,
            title: title,
            description: "These settings will be implemented in a later vertical slice."
        )
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Settings") {
    NavigationStack {
        SettingsView()
    }
}
