import SwiftUI

struct NotificationPreferencesView: View {
    @State private var model: NotificationPreferencesModel

    init(notifications: any NotificationsProviding) {
        _model = State(initialValue: NotificationPreferencesModel(notifications: notifications))
    }

    var body: some View {
        content
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await model.load()
            }
            .onDisappear {
                Task {
                    await model.flush()
                }
            }
            .alert(
                "Settings not saved",
                isPresented: Binding(
                    get: { model.saveFailure != nil },
                    set: { isPresented in
                        if isPresented == false {
                            model.clearSaveFailure()
                        }
                    }
                )
            ) {
                Button("OK") {
                    model.clearSaveFailure()
                }
            } message: {
                Text(model.saveFailure?.message ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            LoadingScreen()
        case let .loaded(preferences):
            settings(preferences)
        case let .failed(reason):
            FailureView(title: "Settings unavailable", reason: reason) {
                await model.retry()
            }
        }
    }

    private func settings(_ preferences: NotificationPreferences) -> some View {
        List {
            Section {
                Toggle("In the app", isOn: toggle(\.channels.inApp))
            } header: {
                Text("Deliver")
            } footer: {
                Text("Push notifications aren't available yet.")
            }

            Section("Tell me about") {
                Toggle("Upcoming releases", isOn: toggle(\.events.releaseApproaching))
                Toggle("Release date changes", isOn: toggle(\.events.releaseDateChanged))
            }

            Section {
                ForEach(TimingPreset.inApproachOrder, id: \.self) { preset in
                    TimingRow(
                        preset: preset,
                        isSelected: preferences.timingPresets.contains(preset)
                    ) {
                        model.edit { $0.timingPresets.toggle(preset) }
                    }
                }
            } header: {
                Text("How far ahead")
            } footer: {
                Text("Applies to upcoming releases. Pick as many as you like.")
            }
            // Nothing here has an effect while the event itself is off.
            .disabled(preferences.events.releaseApproaching == false)
        }
    }

    private func toggle(
        _ field: WritableKeyPath<NotificationPreferences, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { model.preferences?[keyPath: field] ?? false },
            set: { isOn in model.edit { $0[keyPath: field] = isOn } }
        )
    }
}

private struct TimingRow: View {
    let preset: TimingPreset
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                Text(preset.label)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private typealias TimingPreset = NotificationPreferences.TimingPreset

private extension TimingPreset {
    /// Furthest ahead first, so the list reads as a release approaching.
    static let inApproachOrder: [TimingPreset] = [
        .days30Before, .days7Before, .hours24Before, .onDay,
    ]

    var label: String {
        switch self {
        case .onDay: "On release day"
        case .hours24Before: "A day before"
        case .days7Before: "A week before"
        case .days30Before: "A month before"
        }
    }
}

private extension Array where Element == TimingPreset {
    /// Kept in the order the screen lists them, so a saved copy coming back
    /// from the server does not reorder the rows.
    mutating func toggle(_ preset: TimingPreset) {
        if contains(preset) {
            removeAll { $0 == preset }
        } else {
            self = TimingPreset.inApproachOrder.filter { $0 == preset || contains($0) }
        }
    }
}

#Preview("Preferences") {
    NavigationStack {
        NotificationPreferencesView(notifications: PreviewNotifications())
    }
}
