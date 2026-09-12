import SwiftUI

struct SignInView: View {
    var prompt: String?

    @Environment(SessionStore.self) private var session
    @Environment(\.accounts) private var accounts
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var validationMessage: String?
    @FocusState private var focus: Field?

    private enum Field {
        case email
        case password
    }

    private var footerMessage: String? {
        validationMessage ?? session.signInFailure?.message
    }

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
                AuthField(icon: "envelope") {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                }

                AuthField(icon: "lock") {
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
                if let footerMessage {
                    Text(footerMessage)
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
        .onChange(of: email) { clearMessages() }
        .onChange(of: password) { clearMessages() }
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

        if email.contains("@") == false {
            validationMessage = "Enter the email address you signed up with."
            focus = .email
            return
        }

        if password.isEmpty {
            validationMessage = "Enter your password."
            focus = .password
            return
        }

        validationMessage = nil
        focus = nil
        Task {
            await session.signIn(email: email, password: password)
        }
    }

    private func clearMessages() {
        validationMessage = nil
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
