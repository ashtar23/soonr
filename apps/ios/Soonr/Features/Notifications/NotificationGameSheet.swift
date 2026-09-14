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
    @State private var game: NotificationGameStore?

    var body: some View {
        NavigationStack {
            List {
                ForEach(records) { record in
                    row(for: record)
                        .hidingOuterSeparators(
                            isFirst: record.id == records.first?.id,
                            isLast: record.id == records.last?.id
                        )
                        .unreadRowBackground(record.isRead == false)
                        .swipeActions(edge: .trailing) {
                            if record.isRead == false {
                                Button("Mark read", systemImage: "envelope.open") {
                                    Task {
                                        await game?.markRead(id: record.id)
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
        .task {
            let game =
                game
                ?? NotificationGameStore(
                    titleID: group.titleID,
                    showing: group.records,
                    in: notifications
                )
            self.game = game
            await game.load()
        }
    }

    /// What the server says this game has said, or what the list had until it
    /// answers.
    private var records: [NotificationRecord] {
        game?.records ?? group.records
    }

    /// Reading is what the rows are for; going to the game is what the button
    /// is for. A row that also navigated made the button decorative and the
    /// whole sheet a single large tap target.
    private func row(for record: NotificationRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Which reminder it was, because four of them fire for one release
            // and otherwise every line reads as the same sentence about the
            // same date, told apart only by its timestamp.
            Text(record.payload.timingPreset?.label ?? record.message)
                .font(.subheadline)
                .fontWeight(record.isRead ? .regular : .semibold)
                .foregroundStyle(.primary)

            if detail(for: record).isEmpty == false {
                Text(detail(for: record))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// When it arrived, and what it said if the reminder above did not already
    /// say it.
    private func detail(for record: NotificationRecord) -> String {
        [
            record.payload.timingPreset == nil
                ? nil : NotificationCaption.text(for: record, now: now),
            NotificationTimestamp.text(record.createdAt, now: now),
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
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
