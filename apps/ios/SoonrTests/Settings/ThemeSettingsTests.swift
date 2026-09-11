import Foundation
import SwiftUI
import Testing

@testable import Soonr

@MainActor
struct ThemeSettingsTests {
    @Test
    func defaultsToSystemAppearanceAndTheSoonrAccent() {
        let settings = ThemeSettings(defaults: Self.emptyDefaults())

        #expect(settings.appearance == .system)
        #expect(settings.accent == .soonr)
    }

    @Test
    func choicesSurviveARelaunch() {
        let defaults = Self.emptyDefaults()

        let settings = ThemeSettings(defaults: defaults)
        settings.appearance = .dark
        settings.accent = .teal

        let relaunched = ThemeSettings(defaults: defaults)
        #expect(relaunched.appearance == .dark)
        #expect(relaunched.accent == .teal)
    }

    @Test
    func unknownStoredValuesFallBackToTheDefaults() {
        let defaults = Self.emptyDefaults()
        defaults.set("sepia", forKey: "settings.appearance")
        defaults.set("chartreuse", forKey: "settings.accent")

        let settings = ThemeSettings(defaults: defaults)

        #expect(settings.appearance == .system)
        #expect(settings.accent == .soonr)
    }

    @Test(arguments: [
        (AppearanceSetting.system, ColorScheme?.none),
        (.light, .light),
        (.dark, .dark),
    ])
    func appearanceMapsToAColorScheme(setting: AppearanceSetting, expected: ColorScheme?) {
        #expect(setting.colorScheme == expected)
    }

    @Test
    func everyAccentOptionHasAVisibleLabel() {
        #expect(AccentOption.allCases.isEmpty == false)
        #expect(AccentOption.allCases.allSatisfy { $0.label.isEmpty == false })
        #expect(Set(AccentOption.allCases.map(\.rawValue)).count == AccentOption.allCases.count)
    }

    private static func emptyDefaults() -> UserDefaults {
        let suite = "tests.theme.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
