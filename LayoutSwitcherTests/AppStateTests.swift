import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct AppStateTests {
    private static func makeDefaults(_ testName: String = #function) -> UserDefaults? {
        let suiteName = "LayoutSwitcherTests.AppState.\(testName)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create test UserDefaults suite")
            return nil
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func romanianDiacriticsSettingPersistsAcrossInstances() {
        let suiteName = "LayoutSwitcherTests.AppState.romanianDiacriticsSettingPersistsAcrossInstances"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create test UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let first = AppState(defaults: defaults)
        #expect(!first.autoAddRomanianDiacritics)

        first.autoAddRomanianDiacritics = true

        let second = AppState(defaults: defaults)
        #expect(second.autoAddRomanianDiacritics)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func detectionSensitivityPersistsAcrossInstances() {
        let suiteName = "LayoutSwitcherTests.AppState.detectionSensitivityPersistsAcrossInstances"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create test UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let first = AppState(defaults: defaults)
        #expect(first.detectionSensitivity == .balanced)

        first.detectionSensitivity = .aggressive

        let second = AppState(defaults: defaults)
        #expect(second.detectionSensitivity == .aggressive)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func snoozeDurationPersistsAndClamps() {
        let suiteName = "LayoutSwitcherTests.AppState.snoozeDurationPersistsAndClamps"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create test UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        defaults.set(999, forKey: "settings.snoozeDurationMinutes")
        let invalid = AppState(defaults: defaults)
        #expect(invalid.snoozeDuration == .fiveMinutes)

        invalid.snoozeDuration = .sixtyMinutes
        let restored = AppState(defaults: defaults)
        #expect(restored.snoozeDuration == .sixtyMinutes)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func activeSnoozeRemainingClearsExpiredPause() {
        var now = Date(timeIntervalSince1970: 1_000)
        guard let defaults = Self.makeDefaults() else { return }
        let state = AppState(defaults: defaults, now: { now })
        state.snoozeDuration = .fiveMinutes
        state.startSnooze()

        #expect(state.activeSnoozeRemaining != nil)

        now = now.addingTimeInterval(301)
        #expect(state.activeSnoozeRemaining == nil)
        #expect(state.snoozedUntil == nil)
    }
}
