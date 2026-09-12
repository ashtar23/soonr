import SwiftUI

struct AccountView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        NavigationStack {
            content
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
    private var content: some View {
        switch session.state {
        case .restoring:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .signedOut:
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
        case let .signedIn(user):
            SignedInAccount(user: user) {
                await session.signOut()
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

private struct SignedInAccount: View {
    let user: UserSession
    let signOut: () async -> Void

    var body: some View {
        List {
            Section("Signed in") {
                LabeledContent("Email", value: user.email ?? "Unknown")
            }

            Section {
                Button("Sign out", role: .destructive) {
                    Task {
                        await signOut()
                    }
                }
            }
        }
    }
}

#Preview("Signed out") {
    AccountView()
        .environment(SessionStore(authentication: PreviewAuthentication()))
}

#Preview("Signed in") {
    AccountView()
        .environment(
            SessionStore(authentication: PreviewAuthentication(restored: .preview))
        )
}
