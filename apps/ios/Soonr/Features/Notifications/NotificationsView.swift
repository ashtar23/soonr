import SwiftUI

struct NotificationsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(NotificationsStore.self) private var notifications

    @State private var isPresentingSignIn = false

    private let details: TitleDetailsDependencies

    init(details: TitleDetailsDependencies) {
        self.details = details
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Notifications")
                .navigationDestination(for: TitleDestination.self) { destination in
                    TitleDetailsView(destination: destination, dependencies: details)
                }
        }
        // On the stack rather than on `content`, which signing in replaces.
        .sheet(isPresented: $isPresentingSignIn) {
            SignInSheet(prompt: "Sign in to hear when the games you follow arrive.")
        }
        // The root loads once per session, and never again; opening the tab is
        // the way back from a failed load. An already-loaded list is left alone.
        .task {
            guard case .signedIn = session.state, notifications.state.records == nil else {
                return
            }

            await notifications.load()
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
            // An empty inbox is the state most likely to be pulled on, and the
            // one with no list to pull.
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

    var body: some View {
        List {
            ForEach(records) { record in
                NavigationLink(value: record.destination) {
                    NotificationRow(record: record)
                }
            }
        }
        .listStyle(.plain)
        .accessibilityLabel("Notifications")
    }
}

private extension NotificationRecord {
    /// The notification points at a title by id; the name is what the details
    /// screen shows until its own request answers.
    var destination: TitleDestination {
        TitleDestination(id: destinationTitleID, name: titleName)
    }
}

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
            initialValue: SessionStore(authentication: PreviewAuthentication(restored: restored))
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
