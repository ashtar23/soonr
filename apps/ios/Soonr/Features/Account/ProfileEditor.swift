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
    @State private var availability: UsernameAvailability
    @State private var isConfirmingDiscard = false
    @FocusState private var focused: Field?

    private enum Field {
        case username
        case displayName
        case bio
    }

    init(profile: UserProfile, accounts: any AccountCreating) {
        self.profile = profile
        _edit = State(initialValue: ProfileEdit(from: profile))
        _availability = State(initialValue: UsernameAvailability(accounts: accounts))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // The same indicator sign-up uses, so a name reads as free
                    // or taken the same way wherever it is chosen.
                    HStack(spacing: 12) {
                        TextField("Username", text: $edit.username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused, equals: .username)

                        FieldStatusIndicator(status: availability.status)
                    }
                } header: {
                    Text("Username")
                } footer: {
                    if let message = availability.status.message {
                        Text(message)
                            .foregroundStyle(.red)
                    } else {
                        Text("How people find you. Yours if nobody else has taken it.")
                    }
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

            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            // A swipe is too easy to make by accident to be allowed to throw
            // away a bio someone has been writing. Once anything has changed,
            // leaving goes through Cancel, which asks.
            .interactiveDismissDisabled(hasChanges || profiles.isSaving)
            .task(id: edit.username) {
                await availability.check(edit.username, owned: profile.username)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges {
                            isConfirmingDiscard = true
                        } else {
                            dismiss()
                        }
                    }
                    // Anchored to the button, so on a wide screen it opens
                    // from what was tapped rather than the bottom edge.
                    .confirmationDialog(
                        "Discard your changes?",
                        isPresented: $isConfirmingDiscard,
                        titleVisibility: .visible
                    ) {
                        Button("Discard changes", role: .destructive) {
                            dismiss()
                        }
                        Button("Keep editing", role: .cancel) {}
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

    private var hasChanges: Bool {
        edit != ProfileEdit(from: profile)
    }

    private var canSave: Bool {
        // A name already known to be taken is not worth a round trip to be
        // told so again. One still being checked is allowed through: the
        // database decides on save either way.
        guard profiles.isSaving == false,
            edit.bio.count <= bioLimit,
            availability.status.isProblem == false
        else {
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
            ProfileEditor(profile: profile, accounts: PreviewTitleCatalog())
                .environment(profiles)
        }
    }

#endif
