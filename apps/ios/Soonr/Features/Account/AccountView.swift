import SwiftUI

struct AccountView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ProfileStore.self) private var profiles
    @State private var isPresentingSignIn = false
    @State private var isEditingProfile = false

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
        .sheet(isPresented: $isEditingProfile) {
            if let profile = profiles.state.profile {
                ProfileEditor(profile: profile)
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
            SignedOutAccount {
                isPresentingSignIn = true
            }
        case let .signedIn(user):
            SignedInAccount(
                user: user,
                profile: profiles.state,
                isSigningOut: session.isSigningOut,
                editProfile: { isEditingProfile = true },
                setVisibility: { profiles.setWatchlistVisibility($0) },
                retryProfile: { await profiles.retry(userID: user.userID) }
            ) {
                await session.signOut()
            }
            // A change made on the way out still has its timer running, so it
            // is sent rather than lost.
            .onDisappear {
                Task { await profiles.flushWatchlistVisibility() }
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

/// Who you are, and the few things about you that are not app behaviour.
///
/// Anything that answers "how should the app work" lives behind the gear
/// instead. What is left here is your name, who gets to see what, and the
/// account itself — which is why the screen leads with the profile rather than
/// with a row that says you are signed in.
private struct SignedInAccount: View {
    let user: UserSession
    let profile: ProfileState
    let isSigningOut: Bool
    let editProfile: () -> Void
    let setVisibility: (WatchlistVisibility) -> Void
    let retryProfile: () async -> Void
    let signOut: () async -> Void

    /// Reads what the screen is showing and writes through the store, which
    /// answers immediately and saves behind the tap.
    private var visibility: Binding<WatchlistVisibility> {
        Binding(
            get: { profile.profile?.watchlistVisibility ?? .friends },
            set: { setVisibility($0) }
        )
    }

    var body: some View {
        List {
            Section {
                header
            }

            if let profile = profile.profile {
                Section {
                    // A menu rather than a screen of its own: three options do
                    // not earn a push, and the one that is chosen explains
                    // itself underneath instead of inside.
                    Picker("Watchlist visibility", selection: visibility) {
                        ForEach(WatchlistVisibility.allCases, id: \.self) { visibility in
                            Text(visibility.label).tag(visibility)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text(profile.watchlistVisibility.explanation)
                }
            }

            Section("Account") {
                LabeledContent("Email", value: user.email ?? "—")
                    .lineLimit(1)
                    .truncationMode(.middle)

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

    /// The whole row opens the editor, rather than a pencil sitting beside it:
    /// there is one thing to do with your own profile here, and the row is
    /// already the size of a target.
    @ViewBuilder
    private var header: some View {
        switch profile {
        case .loading:
            HStack(spacing: 14) {
                InitialsAvatar(name: fallbackName)
                ProgressView()
            }
            .padding(.vertical, 6)
        case let .loaded(profile):
            Button(action: editProfile) {
                HStack(spacing: 14) {
                    InitialsAvatar(name: avatarName(for: profile))

                    identity(for: profile)

                    Spacer(minLength: 0)

                    // Drawn rather than pushed: this row opens a sheet, and a
                    // NavigationLink would promise a screen you can come back
                    // from without deciding anything.
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Edits your profile")
        case let .failed(reason):
            VStack(alignment: .leading, spacing: 8) {
                Text(reason.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Try again") {
                    Task { await retryProfile() }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func identity(for profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(profile.title(fallback: fallbackName))
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            // An account made before signup asked for a username has none, and
            // saying so is what sends someone to set one.
            Text(profile.username.map { "@\($0)" } ?? "No username yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let bio = profile.bio {
                Text(bio)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
        .multilineTextAlignment(.leading)
    }

    private var fallbackName: String {
        user.email ?? "Your account"
    }

    /// Deliberately not `title(fallback:)`: that leads with "@reader", and the
    /// initial of a handle is the at sign.
    private func avatarName(for profile: UserProfile) -> String {
        profile.displayName ?? profile.username ?? fallbackName
    }
}

#if DEBUG

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

#endif
