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
    @State private var realtime: NotificationsRealtime

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let dependencies = AppDependencies.live()
        self.dependencies = dependencies
        _session = State(initialValue: SessionStore(authentication: dependencies.authentication))
        _watchlist = State(initialValue: WatchlistStore(watchlist: dependencies.watchlist))
        _pushRegistration = State(
            initialValue: PushRegistrationStore(notifications: dependencies.notifications)
        )

        let notifications = NotificationsStore(notifications: dependencies.notifications)
        let preferences = NotificationPreferencesStore(notifications: dependencies.notifications)
        _notifications = State(initialValue: notifications)
        _notificationPreferences = State(initialValue: preferences)
        _realtime = State(
            initialValue: NotificationsRealtime(
                stream: dependencies.notificationStream,
                records: notifications,
                preferences: preferences
            )
        )
    }

    /// The stream is worth holding open only while someone is signed in and
    /// looking at the app. iOS suspends a backgrounded app anyway, so keeping
    /// it would leave the server holding a connection that cannot be read —
    /// push is what covers that stretch, and the refresh on the way back covers
    /// whatever both missed.
    private var isStreamWanted: Bool {
        guard case .signedIn = session.state else {
            return false
        }

        return scenePhase == .active
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
                // Notifications can be turned off in Settings while the app is
                // away, and notifications can be read on another device, so
                // both are re-read on the way back rather than at launch only.
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active, case .signedIn = session.state else {
                        return
                    }

                    Task {
                        await pushRegistration.restore()
                        await notifications.refresh()
                    }
                }
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
                .onChange(of: isStreamWanted, initial: true) { _, wanted in
                    if wanted {
                        realtime.start()
                    } else {
                        realtime.stop()
                    }
                }
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
