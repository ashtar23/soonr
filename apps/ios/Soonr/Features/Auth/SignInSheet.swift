import SwiftUI

/// The app's one sign-in surface, opened only by a deliberate tap: the Account
/// screen, or an action that needs an account. Nothing nags a guest.
///
/// Full height, not a medium detent. Apple reserves the medium detent for
/// progressive disclosure and says to omit it when content needs full
/// visibility; a credential form with a keyboard is a workspace, and every
/// layout fault this sheet has had came from trying to fit one into half a
/// screen.
struct SignInSheet: View {
    var prompt: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SignInView(prompt: prompt)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
        }
        // Painted behind the content rather than with presentationBackground:
        // replacing the presentation's own background takes the sheet out of
        // the system transition, so it vanishes instead of sliding down. iOS 26
        // still needs something opaque here, because it presents sheets over
        // glass and a Form paints none of its own.
        .background(Color(.systemGroupedBackground))
        .presentationDetents([.large])
    }
}

#Preview("From the account screen") {
    Color(.systemGroupedBackground)
        .sheet(isPresented: .constant(true)) {
            SignInSheet()
                .environment(SessionStore(authentication: PreviewAuthentication()))
        }
}

#Preview("Raised by an action") {
    Color(.systemGroupedBackground)
        .sheet(isPresented: .constant(true)) {
            SignInSheet(prompt: "Sign in to add Hades II to your watchlist.")
                .environment(SessionStore(authentication: PreviewAuthentication()))
        }
}
