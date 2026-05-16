import CoreGraphics
import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct LearningCacheTests {
    private static func makeDefaults(_ testName: String = #function) throws -> UserDefaults {
        let suiteName = "LayoutSwitcherTests.LearningCache.\(testName)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private static func makeRecord(
        original: String = "ghbdtn",
        corrected: String = "привет",
        source: LanguageID = .en,
        target: LanguageID = .ru,
        bundleID: String? = "com.test.app"
    ) -> AutoSwitchRecord {
        let chars = original.enumerated().map { index, char in
            WordChar(keyCode: CGKeyCode(index), unicode: String(char), flags: [], timestamp: UInt64(index))
        }
        return AutoSwitchRecord(
            original: chars,
            corrected: corrected,
            targetLanguage: target,
            sourceLanguage: source,
            separator: .space,
            bundleID: bundleID,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private static func makeCache(
        defaults: UserDefaults,
        now: @escaping @MainActor () -> Date = { Date(timeIntervalSince1970: 1_700_000_100) },
        makeEntryID: @escaping @MainActor () -> UUID = {
            UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
        }
    ) -> LearningCache {
        LearningCache(defaults: defaults, now: now, makeEntryID: makeEntryID)
    }

    @Test func recordsUndoAndSuppressesFutureMatch() throws {
        let defaults = try Self.makeDefaults()
        let cache = Self.makeCache(defaults: defaults)
        let record = Self.makeRecord()

        #expect(!cache.shouldSuppress(
            original: "ghbdtn",
            corrected: "привет",
            sourceLanguage: .en,
            targetLanguage: .ru,
            bundleID: "com.test.app"
        ))

        cache.recordUndo(record: record)

        #expect(cache.shouldSuppress(
            original: "ghbdtn",
            corrected: "привет",
            sourceLanguage: .en,
            targetLanguage: .ru,
            bundleID: "com.test.app"
        ))
    }

    @Test func differentBundleIDDoesNotSuppress() throws {
        let defaults = try Self.makeDefaults()
        let cache = Self.makeCache(defaults: defaults)
        cache.recordUndo(record: Self.makeRecord(bundleID: "com.test.app"))

        #expect(!cache.shouldSuppress(
            original: "ghbdtn",
            corrected: "привет",
            sourceLanguage: .en,
            targetLanguage: .ru,
            bundleID: "com.other.app"
        ))
    }

    @Test func differentCorrectionDoesNotSuppress() throws {
        let defaults = try Self.makeDefaults()
        let cache = Self.makeCache(defaults: defaults)
        cache.recordUndo(record: Self.makeRecord(corrected: "привет"))

        #expect(!cache.shouldSuppress(
            original: "ghbdtn",
            corrected: "превед",
            sourceLanguage: .en,
            targetLanguage: .ru,
            bundleID: "com.test.app"
        ))
    }

    @Test func persistsAcrossInstances() throws {
        let defaults = try Self.makeDefaults()
        let cache1 = Self.makeCache(defaults: defaults)
        cache1.recordUndo(record: Self.makeRecord())

        let cache2 = Self.makeCache(defaults: defaults)
        #expect(cache2.shouldSuppress(
            original: "ghbdtn",
            corrected: "привет",
            sourceLanguage: .en,
            targetLanguage: .ru,
            bundleID: "com.test.app"
        ))
    }

    @Test func nilBundleIDSuppressesOnlyForNil() throws {
        let defaults = try Self.makeDefaults()
        let cache = Self.makeCache(defaults: defaults)
        cache.recordUndo(record: Self.makeRecord(bundleID: nil))

        #expect(cache.shouldSuppress(
            original: "ghbdtn",
            corrected: "привет",
            sourceLanguage: .en,
            targetLanguage: .ru,
            bundleID: nil
        ))
        #expect(!cache.shouldSuppress(
            original: "ghbdtn",
            corrected: "привет",
            sourceLanguage: .en,
            targetLanguage: .ru,
            bundleID: "com.test.app"
        ))
    }

    @Test func allEntriesReflectsRecordedUndo() throws {
        let defaults = try Self.makeDefaults()
        let cache = Self.makeCache(defaults: defaults)
        #expect(cache.allEntries().isEmpty)

        cache.recordUndo(record: Self.makeRecord())
        let entries = cache.allEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.original == "ghbdtn")
        #expect(entries.first?.corrected == "привет")
    }

    @Test func allEntriesUsesInjectedIDFactory() throws {
        let defaults = try Self.makeDefaults()
        let expectedID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000123"))
        let cache = Self.makeCache(defaults: defaults, makeEntryID: { expectedID })

        cache.recordUndo(record: Self.makeRecord())

        #expect(cache.allEntries().first?.id == expectedID)
    }

    @Test func removeAtIndexRemovesEntry() throws {
        let defaults = try Self.makeDefaults()
        let cache = Self.makeCache(defaults: defaults)
        cache.recordUndo(record: Self.makeRecord(original: "first", corrected: "первый"))
        cache.recordUndo(record: Self.makeRecord(original: "second", corrected: "второй"))

        cache.remove(at: 0)
        let entries = cache.allEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.original == "first")
    }

    @Test func removeAllClearsEntries() throws {
        let defaults = try Self.makeDefaults()
        let cache = Self.makeCache(defaults: defaults)
        cache.recordUndo(record: Self.makeRecord())

        cache.removeAll()
        #expect(cache.allEntries().isEmpty)
        #expect(!cache.shouldSuppress(
            original: "ghbdtn",
            corrected: "привет",
            sourceLanguage: .en,
            targetLanguage: .ru,
            bundleID: "com.test.app"
        ))
    }
}
