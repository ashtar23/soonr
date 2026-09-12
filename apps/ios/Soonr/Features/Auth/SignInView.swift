import SwiftUI

struct SignInView: View {
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
            } footer: {
                if let failure = session.signInFailure {
                    Text(failure)
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
        }
        .navigationTitle("Sign in")
        .navigationBarTitleDisplayMode(.inline)
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
