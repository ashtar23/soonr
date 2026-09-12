import SwiftUI

struct SignUpView: View {
    /// The sign-up form is taller than sign-in, so the sheet it is pushed into
    /// has to grow once a field takes focus.
    var onBeginEditing: () -> Void = {}

    @Environment(SessionStore.self) private var session

    @State private var model: SignUpModel
    @FocusState private var focus: Field?

    private enum Field {
        case email
        case username
        case password
        case repeatedPassword
    }

    init(accounts: any AccountCreating, onBeginEditing: @escaping () -> Void = {}) {
        _model = State(initialValue: SignUpModel(accounts: accounts))
        self.onBeginEditing = onBeginEditing
    }

    var body: some View {
        @Bindable var model = model

        Form {
            Section {
                TextField("Email", text: $model.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .username }
            } footer: {
                availabilityFooter(model.emailAvailability)
            }

            Section {
                TextField("Username", text: $model.username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
            } footer: {
                usernameFooter
            }

            Section {
                SecureField("Password", text: $model.password)
                    .textContentType(.newPassword)
                    .focused($focus, equals: .password)
                    .submitLabel(.next)
                    .onSubmit { focus = .repeatedPassword }

                SecureField("Repeat password", text: $model.repeatedPassword)
                    .textContentType(.newPassword)
                    .focused($focus, equals: .repeatedPassword)
                    .submitLabel(.go)
                    .onSubmit(submit)
            } footer: {
                passwordFooter
            }

            Section {
                Button(action: submit) {
                    HStack {
                        Text("Create account")
                        if model.isSubmitting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(model.canSubmit == false)
            } footer: {
                if let failure = model.failure {
                    Text(failure.message)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Create account")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.email) {
            await model.checkEmail()
        }
        .task(id: model.username) {
            await model.checkUsername()
        }
        .onChange(of: focus) { _, focus in
            if focus != nil {
                onBeginEditing()
            }
        }
        .onChange(of: model.email) { model.clearFailure() }
        .onChange(of: model.username) { model.clearFailure() }
    }

    @ViewBuilder
    private func availabilityFooter(_ state: AvailabilityState) -> some View {
        switch state {
        case .checking:
            Text("Checking…")
        case .available:
            Label("Available", systemImage: "checkmark")
                .foregroundStyle(.green)
        case let .taken(message):
            Text(message)
                .foregroundStyle(.red)
        case .unchecked, .indeterminate:
            EmptyView()
        }
    }

    @ViewBuilder
    private var usernameFooter: some View {
        switch model.usernameProblem {
        case .tooLong:
            Text("Usernames can be at most \(UsernameRule.maximumLength) characters.")
                .foregroundStyle(.red)
        case .malformed:
            Text(
                "Use letters, numbers, dots and underscores, starting and ending with a letter or number."
            )
            .foregroundStyle(.red)
        case .none:
            availabilityFooter(model.usernameAvailability)
        }
    }

    @ViewBuilder
    private var passwordFooter: some View {
        if model.passwordsMatch == false {
            Text("Those passwords don't match.")
                .foregroundStyle(.red)
        } else {
            Text("At least \(SignUpModel.minimumPasswordLength) characters.")
        }
    }

    private func submit() {
        guard model.canSubmit else {
            return
        }

        focus = nil
        Task {
            if await model.submit() {
                await session.signIn(email: model.email, password: model.password)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SignUpView(accounts: PreviewTitleCatalog())
    }
    .environment(SessionStore(authentication: PreviewAuthentication()))
}
