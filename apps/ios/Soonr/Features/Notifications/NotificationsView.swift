import SwiftUI

enum NotificationsRoute: Hashable {
    case preferences
}

struct NotificationsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(NotificationsStore.self) private var notifications
    @Environment(AppRouter.self) private var router

    @State private var isPresentingSignIn = false

    private let details: TitleDetailsDependencies

    init(details: TitleDetailsDependencies) {
        self.details = details
    }

    var body: some View {
        @Bindable var router = router

        return NavigationStack(path: $router.notificationsPath) {
            content
                .navigationTitle("Notifications")
                .toolbar {
                    // Dimmed rather than gone, so the bar does not
                    // rearrange itself as the last notification is read.
                    if case .signedIn = session.state {
                        ToolbarItem(placement: .topBarTrailing) {
                            menu
                        }
                    }
                }
                .navigationDestination(for: NotificationsRoute.self) { route in
                    switch route {
                    case .preferences:
                        NotificationPreferencesView()
                    }
                }
                .navigationDestination(for: TitleDestination.self) { destination in
                    TitleDetailsView(destination: destination, dependencies: details)
                }
                .navigationDestination(for: NotificationRecord.self) { record in
                    TitleDetailsView(destination: record.destination, dependencies: details)
                        // On the destination rather than the row's action,
                        // so it holds however the screen was reached.
                        .task {
                            await notifications.markRead(id: record.id)
                        }
                }
        }
        // On the stack rather than on `content`, which signing in replaces.
        .sheet(isPresented: $isPresentingSignIn) {
            SignInSheet(prompt: "Sign in to hear when the games you follow arrive.")
        }
        // The root loads once per session, so opening the tab is the way back
        // from a failed load. An already-loaded list is left alone.
        .task {
            guard case .signedIn = session.state, notifications.state.records == nil else {
                return
            }

            await notifications.load()
        }
    }

    private var menu: some View {
        Menu {
            Button("Mark all read", systemImage: "checkmark.circle") {
                Task {
                    await notifications.markAllRead()
                }
            }
            .disabled(notifications.unreadCount == 0)

            NavigationLink(value: NotificationsRoute.preferences) {
                Label("Notification settings", systemImage: "gearshape")
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.state {
        case .restoring:
            LoadingScreen()
        case .signedOut:
            PlaceholderScreen(
                icon: "bell",
                title: "Your notifications",
                description: "Sign in to hear about release dates for the games you follow."
            ) {
                Button("Sign in") {
                    isPresentingSignIn = true
                }
                .prominentButton()
                .controlSize(.large)
            }
        case .signedIn:
            signedInContent
        }
    }

    @ViewBuilder
    private var signedInContent: some View {
        switch notifications.state {
        case .loading:
            LoadingScreen()
        case let .loaded(records) where records.isEmpty:
            PlaceholderScreen(
                icon: "bell",
                title: "No notifications yet",
                description: "Save a game to your watchlist and we'll tell you when it's close."
            )
            // The state most likely to be pulled on, and the one with no
            // list to pull.
            .refreshable {
                await notifications.refresh()
            }
        case let .loaded(records):
            NotificationsList(records: records)
                .refreshable {
                    await notifications.refresh()
                }
        case let .failed(reason):
            FailureView(title: "Notifications unavailable", reason: reason) {
                await notifications.retry()
            }
        }
    }
}

private struct NotificationsList: View {
    let records: [NotificationRecord]

    @Environment(NotificationsStore.self) private var notifications

    var body: some View {
        List {
            ForEach(records) { record in
                // The record, not its title: the destination marks it read
                // and needs to know which it was.
                NavigationLink(value: record) {
                    NotificationRow(record: record)
                }
                .hidingOuterSeparators(
                    isFirst: record.id == records.first?.id,
                    isLast: record.id == records.last?.id
                )
                .unreadRowBackground(record.isRead == false)
                .swipeActions(edge: .trailing) {
                    // One way only: the API can set a notification read and
                    // has no way to put it back.
                    if record.isRead == false {
                        Button("Mark read", systemImage: "envelope.open") {
                            Task {
                                await notifications.markRead(id: record.id)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .accessibilityLabel("Notifications")
    }
}

private extension NotificationRecord {
    var destination: TitleDestination {
        TitleDestination(id: destinationTitleID, name: titleName)
    }
}

#if DEBUG

    #Preview("Notifications") {
        NotificationsPreview(notifications: PreviewNotifications(), restored: .preview)
    }

    #Preview("Nothing yet") {
        NotificationsPreview(notifications: PreviewNotifications(records: []), restored: .preview)
    }

    #Preview("Signed out") {
        NotificationsPreview(notifications: PreviewNotifications(), restored: nil)
    }

    private struct NotificationsPreview: View {
        @State private var notifications: NotificationsStore
        @State private var session: SessionStore

        init(notifications: PreviewNotifications, restored: UserSession?) {
            _notifications = State(initialValue: NotificationsStore(notifications: notifications))
            _session = State(
                initialValue: SessionStore(
                    authentication: PreviewAuthentication(restored: restored))
            )
        }

        var body: some View {
            NotificationsView(details: .preview)
                .environment(session)
                .environment(notifications)
                .task {
                    await session.restore()
                    await notifications.load()
                }
        }
    }

#endif
