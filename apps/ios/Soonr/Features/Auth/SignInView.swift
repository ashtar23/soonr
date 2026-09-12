import SwiftUI

struct SignInView: View {
    var prompt: String?

    @Environment(SessionStore.self) private var session
    @Environment(\.accounts) private var accounts
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var status: [SignUpField: FieldStatus] = [:]
    @FocusState private var focus: SignUpField?

    var body: some View {
        Form {
            Section {
                AuthHeader(
                    icon: "person.crop.circle",
                    title: "Welcome back",
                    subtitle: prompt ?? "Sign in to keep your watchlist with you."
                )
            }
            .listRowBackground(Color.clear)

            Section {
                AuthField(icon: "envelope", message: status[.email]?.message) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                }

                AuthField(icon: "lock", message: status[.password]?.message) {
                    PasswordField(
                        title: "Password",
                        text: $password,
                        isVisible: isPasswordVisible,
                        contentType: .password
                    )
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(submit)
                } accessory: {
                    PasswordVisibilityToggle(isVisible: $isPasswordVisible)
                }
            } footer: {
                if let failure = session.signInFailure {
                    Text(failure.message)
                        .foregroundStyle(.red)
                }
            }
        }
        .listSectionSpacing(.compact)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Sign in")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            AuthActions(title: "Sign in", isBusy: session.isSigningIn, action: submit) {
                NavigationLink("New to Soonr? Create an account") {
                    SignUpView(accounts: accounts)
                }
                .font(.subheadline)
            }
        }
        .onChange(of: focus) { previous, _ in
            if let previous {
                validate(previous)
            }
        }
        .onChange(of: email) { clearMessage(.email) }
        .onChange(of: password) { clearMessage(.password) }
        .onChange(of: session.state) { _, state in
            if case .signedIn = state {
                dismiss()
            }
        }
    }

    private func submit() {
        guard session.isSigningIn == false else {
            return
        }

        validate(.email)
        validate(.password)
        if let unresolved = [SignUpField.email, .password].first(where: {
            status[$0]?.isProblem == true
        }) {
            focus = unresolved
            return
        }

        focus = nil
        Task {
            await session.signIn(email: email, password: password)
        }
    }

    private func validate(_ field: SignUpField) {
        switch field {
        case .email:
            status[.email] =
                email.contains("@")
                ? .idle : .problem("Enter the email address you signed up with.")
        case .password:
            status[.password] = password.isEmpty ? .problem("Enter your password.") : .idle
        case .username, .repeatedPassword:
            break
        }
    }

    private func clearMessage(_ field: SignUpField) {
        status[field] = .idle
        session.clearSignInFailure()
    }
}

#Preview {
    NavigationStack {
        SignInView()
    }
    .environment(SessionStore(authentication: PreviewAuthentication()))
}

#Preview("Raised by an action") {
    NavigationStack {
        SignInView(prompt: "Sign in to add Hades II to your watchlist.")
    }
    .environment(SessionStore(authentication: PreviewAuthentication()))
}
