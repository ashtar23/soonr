import SwiftUI

enum NotificationsRoute: Hashable {
    case preferences
}

struct NotificationsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(NotificationsStore.self) private var notifications
    @Environment(AppRouter.self) private var router

    @State private var isPresentingSignIn = false
    @AppStorage("notifications.groupsByGame") private var groupsByGame = true

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
            // What this list does, apart from where this list goes.
            Section {
                Button("Mark all read", systemImage: "checkmark.circle") {
                    Task {
                        await notifications.markAllRead()
                    }
                }
                .disabled(notifications.unreadCount == 0)

                Toggle(isOn: $groupsByGame) {
                    Label("Group by game", systemImage: "square.stack")
                }

                Toggle(
                    isOn: Binding(
                        get: { notifications.showsUnreadOnly },
                        set: { showsUnreadOnly in
                            Task {
                                await notifications.setShowsUnreadOnly(showsUnreadOnly)
                            }
                        }
                    )
                ) {
                    Label("Unread only", systemImage: "line.3.horizontal.decrease.circle")
                }
            }

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
        case let .loaded(records) where records.isEmpty && notifications.showsUnreadOnly:
            // Nothing unread at all, which the server has now been asked
            // directly rather than inferred from the pages in hand.
            PlaceholderScreen(
                icon: "checkmark.circle",
                title: "Nothing unread",
                description: "Everything has been read."
            ) {
                Button("Show all") {
                    Task {
                        await notifications.setShowsUnreadOnly(false)
                    }
                }
                .prominentButton()
                .controlSize(.large)
            }
            .refreshable {
                await notifications.refresh()
            }
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
            NotificationsList(records: records, groupsByGame: groupsByGame)
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
    let groupsByGame: Bool

    @Environment(NotificationsStore.self) private var notifications
    @State private var openGroup: NotificationGameGroup?
    @ScaledMetric(relativeTo: .headline) private var sheetHeaderHeight: CGFloat = 96
    @ScaledMetric(relativeTo: .subheadline) private var sheetRowHeight: CGFloat = 58
    @ScaledMetric(relativeTo: .headline) private var sheetMaximumHeight: CGFloat = 460

    var body: some View {
        ScrollToTop(tab: .notifications, topID: records.first?.id) {
            list
        }
        .sheet(item: $openGroup) { group in
            NotificationGameSheet(group: group)
                // One detent, sized to what it holds: a panel rather than a
                // thing to be resized. It scrolls inside when a game has been
                // heard from more often than the cap allows for.
                .presentationDetents([.height(sheetHeight(for: group))])
                .presentationDragIndicator(.visible)
        }
    }

    /// The header, a row each, and never more than the cap — which the rows
    /// scroll inside when a game has been heard from more often than it fits.
    /// Measured in scaled points so larger text gets a taller sheet rather than
    /// a cramped one.
    private func sheetHeight(for group: NotificationGameGroup) -> CGFloat {
        let rows = CGFloat(group.records.count)
        return min(sheetHeaderHeight + rows * sheetRowHeight, sheetMaximumHeight)
    }

    private var list: some View {
        List {
            ForEach(NotificationTimeGroup.sections(for: records)) { section in
                Section(section.group.title) {
                    if groupsByGame {
                        ForEach(NotificationGameGroup.groups(for: section.records)) { group in
                            groupRow(group, in: section)
                        }
                    } else {
                        ForEach(section.records) { record in
                            row(record, in: section.records)
                        }
                    }
                }
            }

            // A row of its own rather than an `.onAppear` on the last record, so
            // the trigger does not depend on which record happens to be last.
            if notifications.hasMore {
                LoadingMoreRow()
                    // Keyed on what is loaded so each page re-arms the trigger.
                    // A plain `.task` runs when the row appears and not again,
                    // so a row that stays on screen — a tall screen, a short
                    // page — stopped asking, and paging only resumed once it
                    // had scrolled away and back.
                    .task(id: records.count) {
                        await notifications.loadMore()
                    }
            }
        }
        .listStyle(.plain)
        .accessibilityLabel("Notifications")
    }

    /// A game heard from once is the row it always was; one heard from more
    /// opens what else it said rather than pretending the latest is all of it.
    @ViewBuilder
    private func groupRow(
        _ group: NotificationGameGroup,
        in section: NotificationSection
    ) -> some View {
        if group.isCollapsed {
            Button {
                openGroup = group
            } label: {
                NotificationRow(record: group.latest, hiddenCount: group.hiddenCount)
            }
            .buttonStyle(.plain)
            .hidingOuterSeparators(
                isFirst: group.latest.id == section.records.first?.id,
                isLast: group.latest.id == section.records.last?.id
            )
            .unreadRowBackground(group.hasUnread)
            .swipeActions(edge: .trailing) {
                if group.hasUnread {
                    Button("Mark read", systemImage: "envelope.open") {
                        Task {
                            await notifications.markRead(
                                ids: group.records.filter { $0.isRead == false }.map(\.id)
                            )
                        }
                    }
                }
            }
        } else {
            row(group.latest, in: section.records)
        }
    }

    private func row(
        _ record: NotificationRecord,
        in records: [NotificationRecord]
    ) -> some View {
        // The record, not its title: the destination marks it read and needs
        // to know which it was.
        NavigationLink(value: record) {
            NotificationRow(record: record)
        }
        .hidingOuterSeparators(
            isFirst: record.id == records.first?.id,
            isLast: record.id == records.last?.id
        )
        .unreadRowBackground(record.isRead == false)
        .swipeActions(edge: .trailing) {
            // One way only: the API can set a notification read and has no way
            // to put it back.
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
