import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct PerAppLayoutPreferencesTests {
    private func makeDefaults(_ testName: String = #function) throws -> UserDefaults {
        let suiteName = "PerAppLayoutPreferencesTests.\(testName)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func returnsNilWhenNoPreferenceSet() throws {
        let prefs = PerAppLayoutPreferences(defaults: try makeDefaults())
        #expect(prefs.preferredLayout(for: "com.apple.Safari") == nil)
        #expect(prefs.preferredLayout(for: nil) == nil)
    }

    @Test func setStoresAndReturnsMapping() throws {
        let prefs = PerAppLayoutPreferences(defaults: try makeDefaults())
        prefs.set(layoutID: "com.apple.keylayout.RussianWin", for: "com.tinyspeck.slackmacgap")
        #expect(prefs.preferredLayout(for: "com.tinyspeck.slackmacgap") == "com.apple.keylayout.RussianWin")
    }

    @Test func setOverwritesExistingMapping() throws {
        let prefs = PerAppLayoutPreferences(defaults: try makeDefaults())
        prefs.set(layoutID: "com.apple.keylayout.ABC", for: "com.apple.Safari")
        prefs.set(layoutID: "com.apple.keylayout.RussianWin", for: "com.apple.Safari")
        #expect(prefs.preferredLayout(for: "com.apple.Safari") == "com.apple.keylayout.RussianWin")
    }

    @Test func removeDeletesMapping() throws {
        let prefs = PerAppLayoutPreferences(defaults: try makeDefaults())
        prefs.set(layoutID: "com.apple.keylayout.RussianWin", for: "com.tinyspeck.slackmacgap")
        prefs.remove("com.tinyspeck.slackmacgap")
        #expect(prefs.preferredLayout(for: "com.tinyspeck.slackmacgap") == nil)
    }

    @Test func emptyBundleIDIsIgnored() throws {
        let prefs = PerAppLayoutPreferences(defaults: try makeDefaults())
        prefs.set(layoutID: "com.apple.keylayout.ABC", for: "")
        #expect(prefs.entries.isEmpty)
    }

    @Test func emptyLayoutIDIsIgnored() throws {
        let prefs = PerAppLayoutPreferences(defaults: try makeDefaults())
        prefs.set(layoutID: "", for: "com.apple.Safari")
        #expect(prefs.entries.isEmpty)
    }

    @Test func persistedMappingSurvivesNewInstance() throws {
        let defaults = try makeDefaults()
        let first = PerAppLayoutPreferences(defaults: defaults)
        first.set(layoutID: "com.apple.keylayout.RussianWin", for: "com.tinyspeck.slackmacgap")
        let second = PerAppLayoutPreferences(defaults: defaults)
        #expect(second.preferredLayout(for: "com.tinyspeck.slackmacgap") == "com.apple.keylayout.RussianWin")
    }

    @Test func legacyPlistDictionaryIsMigratedOnLoad() throws {
        let defaults = try makeDefaults()
        // Simulate pre-Codable storage: plain [String: String] under the same key.
        defaults.set(["com.tinyspeck.slackmacgap": "com.apple.keylayout.RussianWin"],
                     forKey: "settings.perAppLayoutPreferences")
        let prefs = PerAppLayoutPreferences(defaults: defaults)
        #expect(prefs.preferredLayout(for: "com.tinyspeck.slackmacgap") == "com.apple.keylayout.RussianWin")
    }

    @Test func sortedEntriesIsAlphabeticallyOrdered() throws {
        let prefs = PerAppLayoutPreferences(defaults: try makeDefaults())
        prefs.set(layoutID: "id1", for: "com.zzz.example")
        prefs.set(layoutID: "id2", for: "com.aaa.example")
        let sorted = prefs.sortedEntries()
        // Bundle IDs without installed apps fall back to bundleID as display name.
        #expect(sorted.first?.bundleID == "com.aaa.example")
        #expect(sorted.last?.bundleID == "com.zzz.example")
    }
}
