import SwiftUI

struct NotificationPreferencesView: View {
    // Shared rather than owned: this screen is reachable from two tabs, and
    // two copies would drift apart and then overwrite each other's changes.
    @Environment(NotificationPreferencesStore.self) private var model

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
                        isSelected: preferences.timingPresets.contains(preset),
                        isOnlyChoice: preferences.timingPresets == [preset]
                    ) {
                        model.edit { $0.toggleTimingPreset(preset) }
                    }
                }
            } header: {
                Text("How far ahead")
            } footer: {
                Text("Applies to upcoming releases. At least one is needed.")
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
    /// The last one standing. Clearing it would send an empty list, which the
    /// server answers by handing back its own default — so the checkmark came
    /// straight back and the tap looked broken.
    let isOnlyChoice: Bool
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
        .disabled(isOnlyChoice)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isOnlyChoice ? "At least one is needed" : "")
    }
}

private typealias TimingPreset = NotificationPreferences.TimingPreset

private extension TimingPreset {
    var label: String {
        switch self {
        case .onDay: "On release day"
        case .hours24Before: "A day before"
        case .days7Before: "A week before"
        case .days30Before: "A month before"
        }
    }
}

#Preview("Preferences") {
    NavigationStack {
        NotificationPreferencesView()
    }
    .environment(NotificationPreferencesStore(notifications: PreviewNotifications()))
}
