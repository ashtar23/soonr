import SwiftUI

struct ThemeSettingsView: View {
    @Environment(ThemeSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppearanceSetting.allCases) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                // The segmented control is already a control; a grouped row
                // background would box it inside another box.
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            } footer: {
                Text("System follows your device's light and dark setting.")
            }

            Section("Accent color") {
                ForEach(AccentOption.allCases) { option in
                    AccentRow(option: option, isSelected: option == settings.accent) {
                        settings.accent = option
                    }
                }
            }
        }
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AccentRow: View {
    let option: AccentOption
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                Circle()
                    .fill(option.color)
                    .frame(width: 22, height: 22)

                Text(option.label)
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

#Preview {
    NavigationStack {
        ThemeSettingsView()
    }
    .environment(ThemeSettings(defaults: .previewDefaults))
}

extension UserDefaults {
    /// An isolated store so previews never mutate the simulator's settings.
    @MainActor
    static let previewDefaults = UserDefaults(suiteName: "preview.theme") ?? .standard
}
