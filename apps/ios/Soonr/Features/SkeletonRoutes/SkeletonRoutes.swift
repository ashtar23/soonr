import SwiftUI

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
