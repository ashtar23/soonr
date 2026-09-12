import SwiftUI

struct SignInView: View {
    /// Shown above the form when an action raised this screen.
    var prompt: String?
    /// Called when the user starts filling the form, so a sheet can make room
    /// for the keyboard.
    var onBeginEditing: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?

    private enum Field {
        case email
        case password
    }

    private var canSubmit: Bool {
        email.contains("@") && password.isEmpty == false && session.isSigningIn == false
    }

    var body: some View {
        Form {
            Section {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(submit)
            } header: {
                if let prompt {
                    Text(prompt)
                        .textCase(nil)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        // iOS 18 and earlier leave almost no gap under a
                        // section header, which pressed a two-line sentence
                        // against the first field. iOS 26 spaces it already and
                        // absorbs the rest.
                        .padding(.bottom, 6)
                }
            } footer: {
                if let failure = session.signInFailure {
                    Text(failure.message)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(action: submit) {
                    HStack {
                        Text("Sign in")
                        if session.isSigningIn {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(canSubmit == false)
            }

            Section {
                NavigationLink("Create account") {
                    SignUpView()
                }
            } footer: {
                Text("New to Soonr? Creating an account takes a moment.")
            }
        }
        .navigationTitle("Sign in")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: focus) { _, focus in
            if focus != nil {
                onBeginEditing()
            }
        }
        .onChange(of: email) { session.clearSignInFailure() }
        .onChange(of: password) { session.clearSignInFailure() }
        .onChange(of: session.state) { _, state in
            if case .signedIn = state {
                dismiss()
            }
        }
    }

    private func submit() {
        guard canSubmit else {
            return
        }

        focus = nil
        Task {
            await session.signIn(email: email, password: password)
        }
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
