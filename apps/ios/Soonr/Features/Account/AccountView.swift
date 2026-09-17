import SwiftUI

struct AccountView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ProfileStore.self) private var profiles
    @Environment(\.accounts) private var accounts
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
                ProfileEditor(profile: profile, accounts: accounts)
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
                counts: profiles.counts,
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
/// instead. What is left is your name, who gets to see what, and the account
/// itself.
///
/// Laid out as your card rather than as the top row of a list: this screen is
/// about one person, and with only a few rows under it a leading row made the
/// whole thing read as a form.
private struct SignedInAccount: View {
    let user: UserSession
    let profile: ProfileState
    let counts: ProfileCounts?
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
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)

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
        // The card is the heading, so a large title above it would say
        // "Account" twice.
        .navigationBarTitleDisplayMode(.inline)
        // A list leaves room above its first section for a header this one
        // does not have, which floated the card well below the bar.
        .contentMargins(.top, 8, for: .scrollContent)
    }

    @ViewBuilder
    private var header: some View {
        switch profile {
        case .loading:
            VStack(spacing: 12) {
                InitialsAvatar(name: fallbackName, diameter: avatarDiameter)
                ProgressView()
            }
            .padding(.vertical, 8)
        case let .loaded(profile):
            VStack(spacing: 12) {
                InitialsAvatar(name: avatarName(for: profile), diameter: avatarDiameter)

                identity(for: profile)

                if let counts {
                    CountsRow(counts: counts)
                        .padding(.top, 4)
                }

                // On the card rather than in the bar. Beside the gear, a text
                // action reads as one control with the symbol, which is the
                // pairing Apple's toolbar guidance warns against.
                Button(action: editProfile) {
                    Text("Edit profile")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
            }
            .padding(.bottom, 4)
        case let .failed(reason):
            VStack(spacing: 8) {
                Text(reason.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Try again") {
                    Task { await retryProfile() }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var avatarDiameter: CGFloat { 84 }

    private func identity(for profile: UserProfile) -> some View {
        VStack(spacing: 4) {
            Text(profile.title(fallback: fallbackName))
                .font(.title2.bold())
                .lineLimit(2)

            // An account made before signup asked for a username has none, and
            // saying so is what sends someone to set one.
            Text(profile.username.map { "@\($0)" } ?? "No username yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let bio = profile.bio {
                Text(bio)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
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

/// Friends first, because that is the number the watchlist setting is about.
private struct CountsRow: View {
    let counts: ProfileCounts

    var body: some View {
        HStack(spacing: 28) {
            count(counts.friends, "Friends")
            count(counts.followers, "Followers")
            count(counts.following, "Following")
        }
    }

    private func count(_ value: Int, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(value, format: .number)
                .font(.headline)
                .monospacedDigit()

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG

    #Preview("Signed out") {
        AccountView()
            .environment(SessionStore(authentication: PreviewAuthentication()))
            .environment(ProfileStore(profiles: PreviewProfiles()))
    }

    #Preview("Signed in") {
        SignedInPreview()
    }

    private struct SignedInPreview: View {
        @State private var profiles = ProfileStore(profiles: PreviewProfiles())

        var body: some View {
            AccountView()
                .environment(
                    SessionStore(authentication: PreviewAuthentication(restored: .preview))
                )
                .environment(profiles)
                .task { await profiles.load(userID: UserProfile.preview.userID) }
        }
    }

#endif
