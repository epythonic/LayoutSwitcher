import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct RecentSwitchesTests {
    private static func fixedID(_ byte: UInt8 = 1) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte))
    }

    private func makeDefaults(_ testName: String = #function) throws -> UserDefaults {
        let suiteName = "RecentSwitchesTests.\(testName)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeEntry(
        id: UUID = Self.fixedID(),
        original: String = "ghbdtn",
        corrected: String = "привет",
        kind: RecentSwitchEntry.Kind = .auto,
        timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> RecentSwitchEntry {
        RecentSwitchEntry(
            id: id,
            original: original,
            corrected: corrected,
            bundleID: "com.test.app",
            bundleName: "Test App",
            kind: kind,
            timestamp: timestamp
        )
    }

    @Test func newInstanceWithoutPersistedDataIsEmpty() throws {
        let recents = RecentSwitches(defaults: try makeDefaults(), makeEntryID: { Self.fixedID() })
        #expect(recents.entries.isEmpty)
    }

    @Test func recordInsertsAtHead() throws {
        let recents = RecentSwitches(defaults: try makeDefaults(), makeEntryID: { Self.fixedID() })
        recents.record(makeEntry(original: "old"))
        recents.record(makeEntry(original: "new"))
        #expect(recents.entries.first?.original == "new")
        #expect(recents.entries.count == 2)
    }

    @Test func recordedEntriesSurviveNewInstance() throws {
        let defaults = try makeDefaults()
        let first = RecentSwitches(defaults: defaults, makeEntryID: { Self.fixedID() })
        first.record(makeEntry(original: "ghbdtn", corrected: "привет"))
        first.record(makeEntry(original: "rfr", corrected: "как", kind: .manual))

        let second = RecentSwitches(defaults: defaults, makeEntryID: { Self.fixedID() })
        #expect(second.entries.count == 2)
        #expect(second.entries.first?.original == "rfr")
        #expect(second.entries.first?.kind == .manual)
        #expect(second.entries.last?.corrected == "привет")
    }

    @Test func entryIDIsStableAcrossPersistence() throws {
        let defaults = try makeDefaults()
        let first = RecentSwitches(defaults: defaults, makeEntryID: { Self.fixedID() })
        let entry = makeEntry(id: Self.fixedID(7))
        first.record(entry)

        let second = RecentSwitches(defaults: defaults, makeEntryID: { Self.fixedID() })
        #expect(second.entries.first?.id == entry.id)
    }

    @Test func clearRemovesAllAndPersists() throws {
        let defaults = try makeDefaults()
        let first = RecentSwitches(defaults: defaults, makeEntryID: { Self.fixedID() })
        first.record(makeEntry())
        first.clear()
        #expect(first.entries.isEmpty)

        let second = RecentSwitches(defaults: defaults, makeEntryID: { Self.fixedID() })
        #expect(second.entries.isEmpty)
    }

    @Test func capacityIsEnforcedOnLoad() throws {
        let defaults = try makeDefaults()
        let store = RecentSwitches(defaults: defaults, makeEntryID: { Self.fixedID() })
        for i in 0..<210 {
            store.record(makeEntry(original: "w\(i)"))
        }
        #expect(store.entries.count == 200)
        #expect(store.entries.first?.original == "w209")
        #expect(store.entries.last?.original == "w10")
    }

    @Test func corruptedDataYieldsEmptyHistory() throws {
        let defaults = try makeDefaults()
        defaults.set(Data([0xff, 0xfe, 0xfd]), forKey: "recentSwitches.entries")
        let recents = RecentSwitches(defaults: defaults, makeEntryID: { Self.fixedID() })
        #expect(recents.entries.isEmpty)
    }

    @Test func legacyDefaultsKeyIsMigratedToNamespacedKey() throws {
        let defaults = try makeDefaults()
        let entry = makeEntry(original: "legacy")
        let data = try JSONEncoder().encode([entry])
        defaults.set(data, forKey: "recentSwitches")

        let recents = RecentSwitches(defaults: defaults, makeEntryID: { Self.fixedID() })

        #expect(recents.entries.first?.original == "legacy")
        #expect(defaults.data(forKey: "recentSwitches.entries") != nil)
    }
}
