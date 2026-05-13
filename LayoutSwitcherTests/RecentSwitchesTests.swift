import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct RecentSwitchesTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "RecentSwitchesTests-\(UUID().uuidString)") ?? .standard
    }

    private func makeEntry(
        original: String = "ghbdtn",
        corrected: String = "привет",
        kind: RecentSwitchEntry.Kind = .auto,
        timestamp: Date = Date()
    ) -> RecentSwitchEntry {
        RecentSwitchEntry(
            original: original,
            corrected: corrected,
            bundleID: "com.test.app",
            bundleName: "Test App",
            kind: kind,
            timestamp: timestamp
        )
    }

    @Test func newInstanceWithoutPersistedDataIsEmpty() {
        let recents = RecentSwitches(defaults: makeDefaults())
        #expect(recents.entries.isEmpty)
    }

    @Test func recordInsertsAtHead() {
        let recents = RecentSwitches(defaults: makeDefaults())
        recents.record(makeEntry(original: "old"))
        recents.record(makeEntry(original: "new"))
        #expect(recents.entries.first?.original == "new")
        #expect(recents.entries.count == 2)
    }

    @Test func recordedEntriesSurviveNewInstance() {
        let defaults = makeDefaults()
        let first = RecentSwitches(defaults: defaults)
        first.record(makeEntry(original: "ghbdtn", corrected: "привет"))
        first.record(makeEntry(original: "rfr", corrected: "как", kind: .manual))

        let second = RecentSwitches(defaults: defaults)
        #expect(second.entries.count == 2)
        #expect(second.entries.first?.original == "rfr")
        #expect(second.entries.first?.kind == .manual)
        #expect(second.entries.last?.corrected == "привет")
    }

    @Test func entryIDIsStableAcrossPersistence() {
        let defaults = makeDefaults()
        let first = RecentSwitches(defaults: defaults)
        let entry = makeEntry()
        first.record(entry)

        let second = RecentSwitches(defaults: defaults)
        #expect(second.entries.first?.id == entry.id)
    }

    @Test func clearRemovesAllAndPersists() {
        let defaults = makeDefaults()
        let first = RecentSwitches(defaults: defaults)
        first.record(makeEntry())
        first.clear()
        #expect(first.entries.isEmpty)

        let second = RecentSwitches(defaults: defaults)
        #expect(second.entries.isEmpty)
    }

    @Test func capacityIsEnforcedOnLoad() {
        let defaults = makeDefaults()
        let store = RecentSwitches(defaults: defaults)
        for i in 0..<210 {
            store.record(makeEntry(original: "w\(i)"))
        }
        #expect(store.entries.count == 200)
        #expect(store.entries.first?.original == "w209")
        #expect(store.entries.last?.original == "w10")
    }

    @Test func corruptedDataYieldsEmptyHistory() {
        let defaults = makeDefaults()
        defaults.set(Data([0xff, 0xfe, 0xfd]), forKey: "recentSwitches.entries")
        let recents = RecentSwitches(defaults: defaults)
        #expect(recents.entries.isEmpty)
    }

    @Test func legacyDefaultsKeyIsMigratedToNamespacedKey() throws {
        let defaults = makeDefaults()
        let entry = makeEntry(original: "legacy")
        let data = try JSONEncoder().encode([entry])
        defaults.set(data, forKey: "recentSwitches")

        let recents = RecentSwitches(defaults: defaults)

        #expect(recents.entries.first?.original == "legacy")
        #expect(defaults.data(forKey: "recentSwitches.entries") != nil)
    }
}
