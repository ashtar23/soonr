import SwiftUI

struct SignUpView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var model: SignUpModel
    @State private var isPasswordVisible = false
    @FocusState private var focus: SignUpField?

    init(accounts: any AccountCreating) {
        _model = State(initialValue: SignUpModel(accounts: accounts))
    }

    var body: some View {
        @Bindable var model = model

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
                AuthField(icon: "envelope", message: model[.email].message) {
                    TextField("Email", text: $model.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .username }
                } accessory: {
                    FieldStatusIndicator(status: model[.email])
                }

                AuthField(icon: "at", message: model[.username].message) {
                    TextField("Username", text: $model.username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                } accessory: {
                    FieldStatusIndicator(status: model[.username])
                }

                AuthField(icon: "lock", message: model[.password].message) {
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

                AuthField(icon: "lock.rotation", message: model[.repeatedPassword].message) {
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
                    FieldStatusIndicator(status: model[.repeatedPassword])
                }
            } footer: {
                if let failure = model.failure {
                    Text(failure.message)
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
        .onChange(of: focus) { previous, _ in
            if let previous {
                model.validate(previous)
            }
        }
        .onChange(of: model.email) { model.fieldChanged(.email) }
        .onChange(of: model.username) { model.fieldChanged(.username) }
        .onChange(of: model.password) { model.fieldChanged(.password) }
        .onChange(of: model.repeatedPassword) { model.fieldChanged(.repeatedPassword) }
    }

    private func submit() {
        guard model.isSubmitting == false else {
            return
        }

        if let unresolved = model.validateAll() {
            focus = unresolved
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

#if DEBUG

    #Preview {
        NavigationStack {
            SignUpView(accounts: PreviewTitleCatalog())
        }
        .environment(SessionStore(authentication: PreviewAuthentication()))
    }

#endif
