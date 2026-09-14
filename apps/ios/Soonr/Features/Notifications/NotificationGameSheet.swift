import SwiftUI

/// Everything one game has been heard from about, and a way to go to it.
///
/// A sheet rather than a pushed screen: two to six lines is not somewhere you
/// go, it is something you glance at. One detent, so it is a panel rather than
/// a thing to be resized, and sized to what it holds — a fixed half screen
/// would be two thirds empty for a game heard from twice.
struct NotificationGameSheet: View {
    let group: NotificationGameGroup
    var now: Date = .now

    @Environment(NotificationsStore.self) private var notifications
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(group.records) { record in
                    row(for: record)
                        .unreadRowBackground(record.isRead == false)
                        .swipeActions(edge: .trailing) {
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
            .navigationTitle(group.latest.titleName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("View game") {
                        openGame()
                    }
                }
            }
        }
    }

    /// Reading is what the rows are for; going to the game is what the button
    /// is for. A row that also navigated made the button decorative and the
    /// whole sheet a single large tap target.
    private func row(for record: NotificationRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(NotificationCaption.text(for: record, now: now) ?? record.message)
                .font(.subheadline)
                .fontWeight(record.isRead ? .regular : .semibold)
                .foregroundStyle(.primary)

            if let timestamp = NotificationTimestamp.text(record.createdAt, now: now) {
                Text(timestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// Going to the game is a change to the path the tab already owns, so the
    /// sheet closes and the stack it closes onto is where the game appears.
    /// Nesting a second navigation stack inside the sheet would have left two
    /// back buttons meaning different things.
    private func openGame() {
        let destination = group.latest.destination
        dismiss()
        router.notificationsPath.append(destination)
    }
}

private extension NotificationRecord {
    var destination: TitleDestination {
        TitleDestination(id: destinationTitleID, name: titleName)
    }
}
