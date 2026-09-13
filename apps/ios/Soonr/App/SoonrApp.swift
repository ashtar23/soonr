import SwiftUI

@main
struct SoonrApp: App {
    private let dependencies: AppDependencies

    // APNs delivers the device token to a UIKit app delegate, which is the
    // only reason this app has one.
    @UIApplicationDelegateAdaptor(PushNotificationsDelegate.self) private var pushDelegate

    @State private var theme = ThemeSettings()
    @State private var session: SessionStore
    @State private var watchlist: WatchlistStore
    @State private var notifications: NotificationsStore
    @State private var notificationPreferences: NotificationPreferencesStore
    @State private var pushRegistration: PushRegistrationStore
    @State private var router = AppRouter()

    init() {
        let dependencies = AppDependencies.live()
        self.dependencies = dependencies
        _session = State(initialValue: SessionStore(authentication: dependencies.authentication))
        _watchlist = State(initialValue: WatchlistStore(watchlist: dependencies.watchlist))
        _notifications = State(
            initialValue: NotificationsStore(notifications: dependencies.notifications)
        )
        _notificationPreferences = State(
            initialValue: NotificationPreferencesStore(notifications: dependencies.notifications)
        )
        _pushRegistration = State(
            initialValue: PushRegistrationStore(notifications: dependencies.notifications)
        )
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(dependencies: dependencies)
                .environment(theme)
                .environment(session)
                .environment(watchlist)
                .environment(notifications)
                .environment(notificationPreferences)
                .environment(pushRegistration)
                .environment(router)
                .environment(\.accounts, dependencies.accounts)
                .tint(theme.accent.color)
                .preferredColorScheme(theme.appearance.colorScheme)
                .task {
                    await session.restore()
                }
                .task {
                    await pushRegistration.restore()
                }
                // A token can arrive before or after the session is known, so
                // the store holds it and uploads once both are true.
                .task {
                    for await token in PushDeviceTokens.tokens {
                        await pushRegistration.tokenReceived(token)
                    }
                }
                // Tapping a push opens the game it is about, and reads the
                // notification behind it so the badge agrees with the screen.
                // The icon mirrors what the app shows: a push leaves a number
                // there that only the app can take down.
                .task(id: notifications.unreadCount) {
                    await pushRegistration.showBadge(notifications.unreadCount)
                }
                .task {
                    for await opened in OpenedPushNotifications.opened {
                        router.open(opened)
                        await notifications.markRead(id: opened.notificationID)
                    }
                }
                // A rejected session ends here rather than leaving a screen
                // offering a retry that can only fail again.
                .task {
                    for await _ in dependencies.rejectedSessions {
                        await session.signOut()
                    }
                }
                // Loaded as soon as there is a session, so a bookmark is
                // already known by the time any title is opened, and dropped on
                // sign out rather than left for the next account.
                .task(id: session.state) {
                    switch session.state {
                    case .restoring:
                        return
                    case .signedOut:
                        watchlist.clear()
                        notifications.clear()
                        notificationPreferences.clear()
                        router.reset()
                        await pushRegistration.signedOut()
                    case .signedIn:
                        await pushRegistration.signedIn()
                        await withTaskGroup(of: Void.self) { group in
                            group.addTask { await watchlist.load() }
                            group.addTask { await notifications.load() }
                        }
                    }
                }
        }
    }
}
