import SwiftUI

struct AccountView: View {
    @Environment(SessionStore.self) private var session
    @State private var isPresentingSignIn = false

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
        // Attached to the stack, not to `content`: signing in switches that
        // view, and a sheet attached to it is torn off without animating.
        .sheet(isPresented: $isPresentingSignIn) {
            SignInSheet()
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
            SignedOutAccount {
                isPresentingSignIn = true
            }
        case let .signedIn(user):
            SignedInAccount(user: user, isSigningOut: session.isSigningOut) {
                await session.signOut()
            }
        }
    }
}

/// Creating an account lives inside the sign-in sheet, so this screen carries
/// a single action.
private struct SignedOutAccount: View {
    let signIn: () -> Void

    var body: some View {
        ScrollView {
            SignedOutAccountContent(signIn: signIn)
                // Centres the block rather than leaving it top-heavy, while
                // still scrolling once large text sizes make it taller than
                // the screen.
                .containerRelativeFrame(.vertical, alignment: .center)
        }
    }
}

/// Split from its scroll container so a snapshot test can render it:
/// `ImageRenderer` draws nothing for a `ScrollView`.
struct SignedOutAccountContent: View {
    let signIn: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 10) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 60))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text("Your Soonr account")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("Keep your games and release reminders with you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
                benefit("bookmark.fill", "Save games to your watchlist")
                benefit("bell.badge.fill", "Hear about them on release day")
                benefit("arrow.triangle.2.circlepath", "Sync across your devices")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: signIn) {
                Text("Sign in")
                    .frame(maxWidth: .infinity)
            }
            .prominentButton()
            .controlSize(.large)
        }
        // Capped so the button does not stretch the full width of an iPad,
        // and centred in whatever space is left.
        .frame(maxWidth: 380)
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }

    private func benefit(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                // A fixed width keeps the labels aligned when the glyphs are
                // different widths.
                .frame(width: 24)
        }
        .labelStyle(.titleAndIcon)
    }
}

private struct SignedInAccount: View {
    let user: UserSession
    let isSigningOut: Bool
    let signOut: () async -> Void

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.email ?? "Your account")
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text("Signed in")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }

            Section {
                Button(role: .destructive) {
                    Task { await signOut() }
                } label: {
                    HStack {
                        Text("Sign out")
                        if isSigningOut {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isSigningOut)
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
