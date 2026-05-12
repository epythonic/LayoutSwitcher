import CoreGraphics
import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct LearningCacheTests {
    private static func makeDefaults(_ testName: String = #function) -> UserDefaults? {
        let suiteName = "LayoutSwitcherTests.LearningCache.\(testName)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create test UserDefaults suite")
            return nil
        }
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
            timestamp: Date()
        )
    }

    @Test func recordsUndoAndSuppressesFutureMatch() {
        guard let defaults = Self.makeDefaults() else { return }
        let cache = LearningCache(defaults: defaults)
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

    @Test func differentBundleIDDoesNotSuppress() {
        guard let defaults = Self.makeDefaults() else { return }
        let cache = LearningCache(defaults: defaults)
        cache.recordUndo(record: Self.makeRecord(bundleID: "com.test.app"))

        #expect(!cache.shouldSuppress(
            original: "ghbdtn",
            corrected: "привет",
            sourceLanguage: .en,
            targetLanguage: .ru,
            bundleID: "com.other.app"
        ))
    }

    @Test func differentCorrectionDoesNotSuppress() {
        guard let defaults = Self.makeDefaults() else { return }
        let cache = LearningCache(defaults: defaults)
        cache.recordUndo(record: Self.makeRecord(corrected: "привет"))

        #expect(!cache.shouldSuppress(
            original: "ghbdtn",
            corrected: "превед",
            sourceLanguage: .en,
            targetLanguage: .ru,
            bundleID: "com.test.app"
        ))
    }

    @Test func persistsAcrossInstances() {
        guard let defaults = Self.makeDefaults() else { return }
        let cache1 = LearningCache(defaults: defaults)
        cache1.recordUndo(record: Self.makeRecord())

        let cache2 = LearningCache(defaults: defaults)
        #expect(cache2.shouldSuppress(
            original: "ghbdtn",
            corrected: "привет",
            sourceLanguage: .en,
            targetLanguage: .ru,
            bundleID: "com.test.app"
        ))
    }

    @Test func nilBundleIDSuppressesOnlyForNil() {
        guard let defaults = Self.makeDefaults() else { return }
        let cache = LearningCache(defaults: defaults)
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

    @Test func allEntriesReflectsRecordedUndo() {
        guard let defaults = Self.makeDefaults() else { return }
        let cache = LearningCache(defaults: defaults)
        #expect(cache.allEntries().isEmpty)

        cache.recordUndo(record: Self.makeRecord())
        let entries = cache.allEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.original == "ghbdtn")
        #expect(entries.first?.corrected == "привет")
    }

    @Test func removeAtIndexRemovesEntry() {
        guard let defaults = Self.makeDefaults() else { return }
        let cache = LearningCache(defaults: defaults)
        cache.recordUndo(record: Self.makeRecord(original: "first", corrected: "первый"))
        cache.recordUndo(record: Self.makeRecord(original: "second", corrected: "второй"))

        cache.remove(at: 0)
        let entries = cache.allEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.original == "first")
    }

    @Test func removeAllClearsEntries() {
        guard let defaults = Self.makeDefaults() else { return }
        let cache = LearningCache(defaults: defaults)
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
