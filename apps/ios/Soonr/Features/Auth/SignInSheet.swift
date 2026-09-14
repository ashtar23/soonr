import SwiftUI

/// Opened only by a deliberate tap, so nothing nags a guest.
///
/// Full height, not a medium detent: Apple reserves that for progressive
/// disclosure and says to omit it when content needs full visibility. Every
/// layout fault this sheet has had came from fitting a keyboard and a
/// credential form into half a screen.
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

#if DEBUG

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

#endif
