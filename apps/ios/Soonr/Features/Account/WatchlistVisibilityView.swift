import SwiftUI

/// Who can see what you are tracking.
///
/// A screen rather than a control on the account list, because each answer
/// needs a sentence: "friends" means nothing until it says which people, and a
/// privacy decision made from three cramped words is a privacy decision made
/// by guessing.
struct WatchlistVisibilityView: View {
    let profile: UserProfile

    @Environment(ProfileStore.self) private var profiles

    var body: some View {
        List {
            Section {
                ForEach(WatchlistVisibility.allCases, id: \.self) { visibility in
                    Button {
                        Task { await choose(visibility) }
                    } label: {
                        row(for: visibility)
                    }
                    .buttonStyle(.plain)
                    .disabled(profiles.isSaving)
                }
            } footer: {
                Text(
                    "Only your watchlist. Your name and bio are visible to anyone who opens your profile."
                )
            }
        }
        .navigationTitle("Watchlist visibility")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Not saved",
            isPresented: Binding(
                get: { profiles.saveFailure != nil },
                set: { isPresented in
                    if isPresented == false {
                        profiles.clearSaveFailure()
                    }
                }
            )
        ) {
            Button("OK") { profiles.clearSaveFailure() }
        } message: {
            Text(profiles.saveFailure?.message ?? "")
        }
    }

    private var selected: WatchlistVisibility {
        profiles.state.profile?.watchlistVisibility ?? profile.watchlistVisibility
    }

    private func row(for visibility: WatchlistVisibility) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(visibility.label)
                    .foregroundStyle(.primary)

                Text(visibility.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if visibility == selected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(visibility == selected ? [.isButton, .isSelected] : .isButton)
    }

    private func choose(_ visibility: WatchlistVisibility) async {
        guard visibility != selected,
            let current = profiles.state.profile
        else {
            return
        }

        var edit = ProfileEdit(from: current)
        edit.watchlistVisibility = visibility
        await profiles.save(edit)
    }
}

#if DEBUG

    #Preview("Visibility") {
        VisibilityPreview()
    }

    private struct VisibilityPreview: View {
        @State private var profiles = ProfileStore(profiles: PreviewProfiles())

        var body: some View {
            NavigationStack {
                WatchlistVisibilityView(profile: .preview)
            }
            .environment(profiles)
            .task { await profiles.load(userID: UserProfile.preview.userID) }
        }
    }

#endif
