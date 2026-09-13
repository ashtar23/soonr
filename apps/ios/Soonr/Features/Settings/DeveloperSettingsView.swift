import SwiftUI

/// What the app knows about itself, for when something does not arrive.
///
/// A build running on a phone has no console to read, so the things that
/// decide whether a push can reach it — permission, which APNs environment
/// this build belongs to, whether the server has the token — are shown here
/// instead of only being logged.
struct DeveloperSettingsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(PushRegistrationStore.self) private var push

    var body: some View {
        List {
            Section("Push") {
                LabeledContent("Permission", value: permission)
                LabeledContent("Environment", value: push.environment.rawValue)
                LabeledContent("Registered", value: push.isRegistered ? "Yes" : "No")
                LabeledContent("Device token", value: token)
                    .textSelection(.enabled)
            }

            Section {
                LabeledContent("Signed in", value: session.state.session == nil ? "No" : "Yes")
                LabeledContent("Build", value: build)
            } header: {
                Text("App")
            } footer: {
                Text(footer)
            }
        }
        .navigationTitle("Developer")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var permission: String {
        switch push.authorization {
        case .undetermined: "Not asked"
        case .authorized: "Granted"
        case .denied: "Denied"
        }
    }

    /// Enough to tell one device's registration from another's in the
    /// database, and short enough to read off a screen.
    private var token: String {
        guard let token = push.deviceToken else {
            return "None"
        }

        return String(token.prefix(12)) + "…"
    }

    private var build: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let number = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(number))"
    }

    private var footer: String {
        guard push.authorization == .authorized else {
            return "A device is registered once notifications are allowed and someone is signed in."
        }

        return session.state.session == nil
            ? "Sign in to register this device."
            : "Registered devices receive a push when a watched game is close."
    }
}

#Preview("Developer") {
    NavigationStack {
        DeveloperSettingsView()
    }
    .environment(SessionStore(authentication: PreviewAuthentication(restored: .preview)))
    .environment(
        PushRegistrationStore(
            notifications: PreviewNotifications(),
            system: PreviewPushAuthorization()
        )
    )
}
