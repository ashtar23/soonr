import SwiftUI

struct NotificationPreferencesView: View {
    // Shared rather than owned: this screen is reachable from two tabs, and
    // two copies would drift apart and then overwrite each other's changes.
    @Environment(NotificationPreferencesStore.self) private var model
    @Environment(PushRegistrationStore.self) private var push
    @Environment(\.openURL) private var openURL

    /// Bumped when a tap asks for something the list cannot give, which is
    /// what the haptic answers.
    @State private var refusedTaps = 0

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
                Toggle("On this device", isOn: pushChannel(preferences))
            } header: {
                Text("Deliver")
            } footer: {
                pushFooter
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
                        if preferences.timingPresets == [preset] {
                            refusedTaps += 1
                        }

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
        // The row stays live and simply declines, the way the selected row of
        // any single-choice list does. Dimming it would have put a dimmed
        // checkmark on screen, which reads as off and on at the same time.
        .sensoryFeedback(.warning, trigger: refusedTaps)
    }

    /// Reads as on only when the server holds the preference *and* iOS still
    /// allows it: permission revoked in Settings means nothing arrives,
    /// whatever the account last saved.
    private func pushChannel(_ preferences: NotificationPreferences) -> Binding<Bool> {
        Binding(
            get: { preferences.channels.push && push.authorization == .authorized },
            set: { isOn in
                Task {
                    await setPushChannel(isOn)
                }
            }
        )
    }

    private func setPushChannel(_ isOn: Bool) async {
        guard isOn else {
            model.edit { $0.channels.push = false }
            return
        }

        // iOS shows its prompt once per install, so after a refusal Settings
        // is the only way back and the switch takes you there. Springing back
        // with nothing else happening left the tap achieving nothing.
        guard push.authorization != .denied else {
            openNotificationSettings()
            return
        }

        // Asking happens on the way on, so the prompt follows a request for
        // notifications rather than arriving unexplained at launch.
        guard await push.requestAuthorization() else {
            return
        }

        model.edit { $0.channels.push = true }
    }

    /// `openNotificationSettingsURLString` lands on Soonr's notification
    /// settings rather than its general page, so the switch that needs turning
    /// on is already on screen.
    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else {
            return
        }

        openURL(url)
    }

    @ViewBuilder
    private var pushFooter: some View {
        switch push.authorization {
        case .undetermined:
            Text("Soonr asks for permission the first time you turn this on.")
        case .authorized:
            Text("Sent to this device, even when Soonr isn't open.")
        case .denied:
            // A footer explains; it does not act. The switch is the control,
            // and this is where it says so — iOS shows its prompt once ever,
            // so Settings is the only way back.
            Text("Notifications are turned off for Soonr in Settings. Tap to turn them back on.")
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
    /// The last one standing, which cannot be cleared: an empty list is a
    /// state the server answers by handing back its own default.
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

#if DEBUG

    #Preview("Preferences") {
        PreferencesPreview(authorization: .authorized)
    }

    #Preview("Push not yet asked for") {
        PreferencesPreview(authorization: .undetermined)
    }

    #Preview("Push refused") {
        PreferencesPreview(authorization: .denied)
    }

    private struct PreferencesPreview: View {
        @State private var preferences = NotificationPreferencesStore(
            notifications: PreviewNotifications()
        )
        @State private var push: PushRegistrationStore

        init(authorization: PushAuthorization) {
            _push = State(
                initialValue: PushRegistrationStore(
                    notifications: PreviewNotifications(),
                    system: PreviewPushAuthorization(authorization: authorization)
                )
            )
        }

        var body: some View {
            NavigationStack {
                NotificationPreferencesView()
            }
            .environment(preferences)
            .environment(push)
            .task {
                await push.restore()
            }
        }
    }

#endif
