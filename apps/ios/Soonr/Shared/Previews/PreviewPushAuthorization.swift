import Foundation

#if DEBUG

    /// Stands in for the system prompt, so previews can show each answer to it.
    struct PreviewPushAuthorization: PushAuthorizing {
        var authorization: PushAuthorization = .authorized
        var grants = true

        func authorization() async -> PushAuthorization {
            authorization
        }

        func requestAuthorization() async -> Bool {
            grants
        }

        func registerForRemoteNotifications() async {}

        func setBadgeCount(_ count: Int) async {}
    }

#endif
