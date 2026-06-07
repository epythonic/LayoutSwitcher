import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct AppStateTests {
    private static func makeDefaults(_ testName: String = #function) throws -> UserDefaults {
        let suiteName = "LayoutSwitcherTests.AppState.\(testName)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func romanianDiacriticsSettingPersistsAcrossInstances() throws {
        let defaults = try Self.makeDefaults()
        let first = AppState(defaults: defaults, now: { Date(timeIntervalSince1970: 0) })
        #expect(!first.autoAddRomanianDiacritics)

        first.autoAddRomanianDiacritics = true

        let second = AppState(defaults: defaults, now: { Date(timeIntervalSince1970: 0) })
        #expect(second.autoAddRomanianDiacritics)

    }

    @Test func detectionSensitivityPersistsAcrossInstances() throws {
        let defaults = try Self.makeDefaults()
        let first = AppState(defaults: defaults, now: { Date(timeIntervalSince1970: 0) })
        #expect(first.detectionSensitivity == .balanced)

        first.detectionSensitivity = .aggressive

        let second = AppState(defaults: defaults, now: { Date(timeIntervalSince1970: 0) })
        #expect(second.detectionSensitivity == .aggressive)

    }

    @Test func detectionSensitivityIsStoredPerLanguagePair() throws {
        let defaults = try Self.makeDefaults()
        let state = AppState(defaults: defaults, now: { Date(timeIntervalSince1970: 0) })

        state.setActiveLanguagePair(.ruEn)
        state.detectionSensitivity = .aggressive

        state.setActiveLanguagePair(.roEn)
        #expect(state.detectionSensitivity == .balanced) // independent default
        state.detectionSensitivity = .conservative

        state.setActiveLanguagePair(.ruEn)
        #expect(state.detectionSensitivity == .aggressive) // ruEn override retained
        #expect(state.detectionSensitivity(for: .roEn) == .conservative)

        // Per-pair overrides persist across instances.
        let reloaded = AppState(defaults: defaults, now: { Date(timeIntervalSince1970: 0) })
        #expect(reloaded.detectionSensitivity(for: .ruEn) == .aggressive)
        #expect(reloaded.detectionSensitivity(for: .roEn) == .conservative)
    }

    @Test func duplicateLetterCorrectionSettingPersistsAcrossInstances() throws {
        let defaults = try Self.makeDefaults()
        let first = AppState(defaults: defaults, now: { Date(timeIntervalSince1970: 0) })
        #expect(!first.correctDuplicateLetters)

        first.correctDuplicateLetters = true

        let second = AppState(defaults: defaults, now: { Date(timeIntervalSince1970: 0) })
        #expect(second.correctDuplicateLetters)
    }

    @Test func doubleCapitalCorrectionSettingPersistsAcrossInstances() throws {
        let defaults = try Self.makeDefaults()
        let first = AppState(defaults: defaults, now: { Date(timeIntervalSince1970: 0) })
        #expect(!first.correctDoubleCapitals)

        first.correctDoubleCapitals = true

        let second = AppState(defaults: defaults, now: { Date(timeIntervalSince1970: 0) })
        #expect(second.correctDoubleCapitals)
    }

    @Test func russianYoSettingPersistsAcrossInstances() throws {
        let defaults = try Self.makeDefaults()
        let first = AppState(defaults: defaults, now: { Date(timeIntervalSince1970: 0) })
        #expect(!first.autoAddRussianYo)

        first.autoAddRussianYo = true

        let second = AppState(defaults: defaults, now: { Date(timeIntervalSince1970: 0) })
        #expect(second.autoAddRussianYo)
    }

    @Test func commonTypoCorrectionSettingPersistsAcrossInstances() throws {
        let defaults = try Self.makeDefaults()
        let first = AppState(defaults: defaults, now: { Date(timeIntervalSince1970: 0) })
        #expect(!first.correctCommonTypos)

        first.correctCommonTypos = true

        let second = AppState(defaults: defaults, now: { Date(timeIntervalSince1970: 0) })
        #expect(second.correctCommonTypos)
    }

    @Test func activeLanguagePairDefaultsToRussianEnglishOnly() throws {
        let defaults = try Self.makeDefaults()
        let state = AppState(defaults: defaults, now: { Date(timeIntervalSince1970: 0) })

        #expect(state.activeLanguagePair == .ruEn)
        #expect(state.enabledLanguageDirections == Set(LanguageDirection.allCases))
        #expect(state.isLanguageDirectionEnabled(source: .en, target: .ru))
        #expect(!state.isLanguageDirectionEnabled(source: .en, target: .uk))
        #expect(!state.isLanguageDirectionEnabled(source: .en, target: .ro))
        #expect(state.enabledCrossLayoutTargets(from: .en) == Set([.ru]))
    }

    @Test func activeLanguagePairPersistsAcrossInstances() throws {
        let defaults = try Self.makeDefaults()
        let first = AppState(defaults: defaults, now: { Date(timeIntervalSince1970: 0) })

        first.setActiveLanguagePair(.roEn)

        let second = AppState(defaults: defaults, now: { Date(timeIntervalSince1970: 0) })

        #expect(second.activeLanguagePair == .roEn)
        #expect(second.isLanguageDirectionEnabled(source: .en, target: .ro))
        #expect(second.isLanguageDirectionEnabled(source: .ro, target: .en))
        #expect(!second.isLanguageDirectionEnabled(source: .en, target: .ru))
        #expect(second.enabledCrossLayoutTargets(from: .en) == Set([.ro]))
    }

    @Test func languageDirectionsPersistWithinActivePair() throws {
        let defaults = try Self.makeDefaults()
        let first = AppState(defaults: defaults, now: { Date(timeIntervalSince1970: 0) })
        first.setLanguageDirection(.enToRu, isEnabled: false)
        first.setLanguageDirection(.roToEn, isEnabled: false)
        first.setActiveLanguagePair(.roEn)

        let second = AppState(defaults: defaults, now: { Date(timeIntervalSince1970: 0) })

        #expect(second.activeLanguagePair == .roEn)
        #expect(!second.isLanguageDirectionEnabled(source: .en, target: .ru))
        #expect(!second.isLanguageDirectionEnabled(source: .ro, target: .en))
        #expect(second.isLanguageDirectionEnabled(source: .en, target: .ro))
        #expect(!second.isLanguageDirectionEnabled(source: .ru, target: .en))
        #expect(second.isLanguageDirectionEnabled(source: .en, target: .en))
    }

    @Test func snoozeDurationPersistsAndClamps() throws {
        let defaults = try Self.makeDefaults()
        defaults.set(999, forKey: "settings.snoozeDurationMinutes")
        let invalid = AppState(defaults: defaults, now: { Date(timeIntervalSince1970: 0) })
        #expect(invalid.snoozeDuration == .fiveMinutes)

        invalid.snoozeDuration = .sixtyMinutes
        let restored = AppState(defaults: defaults, now: { Date(timeIntervalSince1970: 0) })
        #expect(restored.snoozeDuration == .sixtyMinutes)

    }

    @Test func activeSnoozeRemainingClearsExpiredPause() throws {
        var now = Date(timeIntervalSince1970: 1_000)
        let defaults = try Self.makeDefaults()
        let state = AppState(defaults: defaults, now: { now })
        state.snoozeDuration = .fiveMinutes
        state.startSnooze()

        #expect(state.activeSnoozeRemaining != nil)

        now = now.addingTimeInterval(301)
        #expect(state.activeSnoozeRemaining == nil)
        #expect(state.snoozedUntil == nil)
    }
}
