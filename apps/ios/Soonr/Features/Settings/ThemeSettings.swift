import Observation
import SwiftUI

enum AppearanceSetting: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` follows the device setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AccentOption: String, CaseIterable, Identifiable, Sendable {
    case soonr
    case indigo
    case violet
    case teal
    case orange
    case pink

    var id: String { rawValue }

    var label: String {
        switch self {
        case .soonr: "Soonr"
        case .indigo: "Indigo"
        case .violet: "Violet"
        case .teal: "Teal"
        case .orange: "Orange"
        case .pink: "Pink"
        }
    }

    /// System colors already adapt to light and dark; `soonr` reads the
    /// BrandBlue asset, which carries its own light and dark values. The asset
    /// is deliberately not named AccentColor: SwiftUI resolves that name to
    /// the current tint, so the brand swatch would show whichever accent is
    /// active instead of the brand colour.
    var color: Color {
        switch self {
        case .soonr: Color("BrandBlue")
        case .indigo: .indigo
        case .violet: .purple
        case .teal: .teal
        case .orange: .orange
        case .pink: .pink
        }
    }
}

/// App-wide appearance choices, created once at the app root and injected
/// through the environment.
@MainActor
@Observable
final class ThemeSettings {
    var appearance: AppearanceSetting {
        didSet {
            defaults.set(appearance.rawValue, forKey: Key.appearance)
        }
    }

    var accent: AccentOption {
        didSet {
            defaults.set(accent.rawValue, forKey: Key.accent)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let appearance = "settings.appearance"
        static let accent = "settings.accent"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance =
            AppearanceSetting(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        accent = AccentOption(rawValue: defaults.string(forKey: Key.accent) ?? "") ?? .soonr
    }
}
