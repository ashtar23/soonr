import SwiftUI

/// The app's one sign-in surface, opened only by a deliberate tap: the Account
/// screen, or an action that needs an account. Nothing nags a guest while they
/// browse.
///
/// It opens at a medium detent so whatever raised it stays visible behind, and
/// grows to large once the form is being filled in and the keyboard needs the
/// room.
struct SignInSheet: View {
    /// Says why the sheet appeared when an action raised it, so signing in
    /// reads as finishing what the user started.
    var prompt: String?

    @Environment(\.dismiss) private var dismiss
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        NavigationStack {
            SignInView(prompt: prompt) {
                detent = .large
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        // iOS 26 presents sheets over a glass background, and a Form does not
        // paint its own, so whatever sits behind bleeds through the fields.
        // An opaque grouped background is what a form sheet should look like.
        .presentationBackground(Color(.systemGroupedBackground))
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
