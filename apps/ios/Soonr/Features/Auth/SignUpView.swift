import SwiftUI

struct SignUpView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var model: SignUpModel
    @State private var isPasswordVisible = false
    @State private var validationMessage: String?
    @FocusState private var focus: Field?

    private enum Field {
        case email
        case username
        case password
        case repeatedPassword
    }

    init(accounts: any AccountCreating) {
        _model = State(initialValue: SignUpModel(accounts: accounts))
    }

    var body: some View {
        Form {
            Section {
                AuthHeader(
                    icon: "person.crop.circle.badge.plus",
                    title: "Create your account",
                    subtitle: "Save games and hear about them on release day."
                )
            }
            .listRowBackground(Color.clear)

            Section {
                AuthField(icon: "envelope") {
                    TextField("Email", text: $model.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .username }
                } accessory: {
                    AvailabilityIndicator(state: model.emailAvailability)
                }

                AuthField(icon: "at") {
                    TextField("Username", text: $model.username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                } accessory: {
                    AvailabilityIndicator(state: usernameIndicatorState)
                }

                AuthField(icon: "lock") {
                    PasswordField(
                        title: "Password",
                        text: $model.password,
                        isVisible: isPasswordVisible,
                        contentType: .newPassword
                    )
                    .focused($focus, equals: .password)
                    .submitLabel(.next)
                    .onSubmit { focus = .repeatedPassword }
                } accessory: {
                    PasswordVisibilityToggle(isVisible: $isPasswordVisible)
                }

                AuthField(icon: "lock.rotation") {
                    PasswordField(
                        title: "Repeat password",
                        text: $model.repeatedPassword,
                        isVisible: isPasswordVisible,
                        contentType: .newPassword
                    )
                    .focused($focus, equals: .repeatedPassword)
                    .submitLabel(.go)
                    .onSubmit(submit)
                } accessory: {
                    if model.repeatedPassword.isEmpty == false {
                        AvailabilityIndicator(
                            state: model.passwordsMatch ? .available : .taken("")
                        )
                    }
                }
            } footer: {
                if let message = footerMessage {
                    Text(message)
                        .foregroundStyle(.red)
                } else {
                    Text("At least \(SignUpModel.minimumPasswordLength) characters.")
                }
            }
        }
        .listSectionSpacing(.compact)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Create account")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            AuthActions(title: "Create account", isBusy: model.isSubmitting, action: submit) {
                Button("Already have an account? Sign in") {
                    dismiss()
                }
                .font(.subheadline)
            }
        }
        .task(id: model.email) {
            await model.checkEmail()
        }
        .task(id: model.username) {
            await model.checkUsername()
        }
        .onChange(of: model.email) { clearMessages() }
        .onChange(of: model.username) { clearMessages() }
        .onChange(of: model.password) { validationMessage = nil }
        .onChange(of: model.repeatedPassword) { validationMessage = nil }
    }

    private var footerMessage: String? {
        if let validationMessage {
            return validationMessage
        }

        if let failure = model.failure {
            return failure.message
        }

        switch model.usernameProblem {
        case .tooLong:
            return "Usernames can be at most \(UsernameRule.maximumLength) characters."
        case .malformed:
            return "Usernames use letters, numbers, dots and underscores."
        case .none:
            break
        }

        if case let .taken(message) = model.usernameAvailability {
            return message
        }

        if case let .taken(message) = model.emailAvailability {
            return message
        }

        return nil
    }

    /// A locally rejected username never reaches the server, so the row shows
    /// the local verdict rather than a stale check.
    private var usernameIndicatorState: AvailabilityState {
        model.usernameProblem == nil ? model.usernameAvailability : .taken("")
    }

    private func submit() {
        guard model.isSubmitting == false else {
            return
        }

        if model.email.contains("@") == false {
            validationMessage = "Enter an email address you can receive mail at."
            focus = .email
            return
        }

        if model.usernameProblem != nil || model.username.isEmpty {
            validationMessage = "Pick a username of letters, numbers, dots or underscores."
            focus = .username
            return
        }

        if model.password.count < SignUpModel.minimumPasswordLength {
            validationMessage =
                "Use at least \(SignUpModel.minimumPasswordLength) characters for your password."
            focus = .password
            return
        }

        if model.passwordsMatch == false || model.repeatedPassword.isEmpty {
            validationMessage = "Those passwords don't match."
            focus = .repeatedPassword
            return
        }

        validationMessage = nil
        focus = nil
        Task {
            if await model.submit() {
                await session.signIn(email: model.email, password: model.password)
            }
        }
    }

    private func clearMessages() {
        validationMessage = nil
        model.clearFailure()
    }
}

/// Reports a field's state inside its row, so a check does not reflow the form
/// by appearing and disappearing underneath it.
private struct AvailabilityIndicator: View {
    let state: AvailabilityState

    var body: some View {
        switch state {
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .available:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Available")
        case .taken:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Unavailable")
        case .unchecked, .indeterminate:
            EmptyView()
        }
    }
}

#Preview {
    NavigationStack {
        SignUpView(accounts: PreviewTitleCatalog())
    }
    .environment(SessionStore(authentication: PreviewAuthentication()))
}
