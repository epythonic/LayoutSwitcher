import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct SystemSpellCheckerTests {

    private final class FakeChecker: SpellChecking {
        var availableLanguages: [String] = ["en", "ru", "ro"]
        var knownWords: Set<String> = []

        func checkSpelling(
            of stringToCheck: String,
            startingAt startingOffset: Int,
            language: String?,
            wrap wrapFlag: Bool,
            inSpellDocumentWithTag tag: Int,
            wordCount: UnsafeMutablePointer<Int>?
        ) -> NSRange {
            let word = stringToCheck.lowercased()
            if knownWords.contains(word) {
                return NSRange(location: NSNotFound, length: 0)
            }
            return NSRange(location: 0, length: stringToCheck.utf16.count)
        }

        func guesses(
            forWordRange range: NSRange,
            in string: String,
            language: String?,
            inSpellDocumentWithTag tag: Int
        ) -> [String]? {
            []
        }
    }

    @Test func containsKnownWord() {
        let checker = FakeChecker()
        checker.knownWords.insert("hello")
        let dict = SystemSpellCheckerDictionary(language: .en, checker: checker, cacheCapacity: 100)
        #expect(dict.contains("hello"))
    }

    @Test func doesNotContainUnknownWord() {
        let checker = FakeChecker()
        let dict = SystemSpellCheckerDictionary(language: .en, checker: checker, cacheCapacity: 100)
        #expect(!dict.contains("xyzqwerty"))
    }

    @Test func cachesResult() {
        let checker = FakeChecker()
        checker.knownWords.insert("world")
        let dict = SystemSpellCheckerDictionary(language: .en, checker: checker, cacheCapacity: 100)
        _ = dict.contains("world")
        #expect(dict.cachedEntryCount == 1)
        _ = dict.contains("world")
        #expect(dict.cachedEntryCount == 1)
    }

    @Test func evictionWhenCacheFull() {
        let checker = FakeChecker()
        let dict = SystemSpellCheckerDictionary(language: .en, checker: checker, cacheCapacity: 2)
        checker.knownWords = ["a", "b", "c"]
        _ = dict.contains("a")
        _ = dict.contains("b")
        _ = dict.contains("c")
        #expect(dict.cachedEntryCount <= 2)
    }

    @Test func differentLanguagesHaveDifferentISO() {
        let en = SystemSpellCheckerDictionary(language: .en, checker: FakeChecker(), cacheCapacity: 10)
        let ru = SystemSpellCheckerDictionary(language: .ru, checker: FakeChecker(), cacheCapacity: 10)
        let ro = SystemSpellCheckerDictionary(language: .ro, checker: FakeChecker(), cacheCapacity: 10)
        #expect(en.isoLanguage == "en")
        #expect(ru.isoLanguage == "ru")
        #expect(ro.isoLanguage == "ro")
    }
}
