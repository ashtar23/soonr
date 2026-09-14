import SwiftUI

/// Editing your own profile.
///
/// Saved on a button rather than as it is typed. A username can be refused —
/// by a rule, or by somebody else already having it — and a field that saved
/// itself would leave the refusal nowhere to land and the name already gone
/// from the screen.
struct ProfileEditor: View {
    let profile: UserProfile

    @Environment(ProfileStore.self) private var profiles
    @Environment(\.dismiss) private var dismiss

    @State private var edit: ProfileEdit
    @FocusState private var focused: Field?

    private enum Field {
        case username
        case displayName
        case bio
    }

    init(profile: UserProfile) {
        self.profile = profile
        _edit = State(initialValue: ProfileEdit(from: profile))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $edit.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .username)
                } header: {
                    Text("Username")
                } footer: {
                    usernameFooter
                }

                Section {
                    TextField("Display name", text: $edit.displayName)
                        .focused($focused, equals: .displayName)
                } header: {
                    Text("Display name")
                } footer: {
                    Text("Shown instead of your username. Leave it empty to go by your username.")
                }

                Section {
                    TextField("Bio", text: $edit.bio, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($focused, equals: .bio)
                } header: {
                    Text("Bio")
                } footer: {
                    // Counted only once it matters, so the field is not a form
                    // with a number under it until there is something to say.
                    if edit.bio.count > bioLimit - 60 {
                        Text("\(edit.bio.count) of \(bioLimit)")
                            .foregroundStyle(edit.bio.count > bioLimit ? .red : .secondary)
                    }
                }

                Section {
                    Picker("Who can see your watchlist", selection: $edit.watchlistVisibility) {
                        ForEach(WatchlistVisibility.allCases, id: \.self) { visibility in
                            Text(visibility.label).tag(visibility)
                        }
                    }
                } header: {
                    Text("Watchlist")
                } footer: {
                    Text(edit.watchlistVisibility.explanation)
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(canSave == false)
                }
            }
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
    }

    private var bioLimit: Int { 280 }

    /// Answers what the rule can answer here, and leaves the rest to the
    /// server: it owns the reserved names and it owns who already has one.
    @ViewBuilder
    private var usernameFooter: some View {
        switch UsernameRule.problem(with: edit.username) {
        case .tooLong:
            Text("Usernames are at most \(UsernameRule.maximumLength) characters.")
                .foregroundStyle(.red)
        case .malformed where edit.username.isEmpty == false:
            Text("Letters, numbers, dots and underscores, starting and ending with one.")
                .foregroundStyle(.red)
        default:
            Text("How people find you. Yours if nobody else has taken it.")
        }
    }

    private var canSave: Bool {
        guard profiles.isSaving == false, edit.bio.count <= bioLimit else {
            return false
        }

        // An empty username is allowed only while it was already empty: this
        // screen can give an account its first one, but not take it away.
        if edit.username.isEmpty {
            return profile.username == nil && changedSomethingElse
        }

        return UsernameRule.problem(with: edit.username) == nil
            && edit != ProfileEdit(from: profile)
    }

    private var changedSomethingElse: Bool {
        var untouched = ProfileEdit(from: profile)
        untouched.username = edit.username
        return edit != untouched
    }

    private func save() async {
        focused = nil

        if await profiles.save(edit) {
            dismiss()
        }
    }
}

#if DEBUG

    #Preview("Editing") {
        ProfileEditorPreview(profile: .preview)
    }

    #Preview("No username yet") {
        ProfileEditorPreview(profile: .previewUnnamed)
    }

    private struct ProfileEditorPreview: View {
        let profile: UserProfile

        @State private var profiles = ProfileStore(profiles: PreviewProfiles())

        var body: some View {
            ProfileEditor(profile: profile)
                .environment(profiles)
        }
    }

#endif
