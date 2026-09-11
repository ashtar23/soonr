import SwiftUI

struct AccountView: View {
    var body: some View {
        NavigationStack {
            PlaceholderScreen(
                icon: "person.crop.circle",
                title: "Your Soonr account",
                description: "Sign in to manage your watchlist and notification preferences."
            ) {
                VStack(spacing: 12) {
                    signInLink
                    signUpLink
                }
            }
            .navigationTitle("Account")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var signInLink: some View {
        if #available(iOS 26, *) {
            NavigationLink("Sign in") {
                SignInView()
            }
            .buttonStyle(.glassProminent)
        } else {
            NavigationLink("Sign in") {
                SignInView()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var signUpLink: some View {
        if #available(iOS 26, *) {
            NavigationLink("Create account") {
                SignUpView()
            }
            .buttonStyle(.glass)
        } else {
            NavigationLink("Create account") {
                SignUpView()
            }
            .buttonStyle(.bordered)
        }
    }
}

#Preview {
    AccountView()
}
