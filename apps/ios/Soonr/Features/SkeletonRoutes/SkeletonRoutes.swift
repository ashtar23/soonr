import SwiftUI

struct SignInView: View {
    var body: some View {
        PlaceholderScreen(
            icon: "person.badge.key",
            title: "Sign in",
            description: "Email and password authentication will be added in the auth slice."
        )
        .navigationTitle("Sign in")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SignUpView: View {
    var body: some View {
        PlaceholderScreen(
            icon: "person.badge.plus",
            title: "Create your account",
            description: "Account and profile setup will be added in the auth slice."
        )
        .navigationTitle("Create account")
        .navigationBarTitleDisplayMode(.inline)
    }
}
