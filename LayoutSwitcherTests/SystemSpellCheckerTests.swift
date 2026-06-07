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

    private struct FakeSuggestionProvider: SpellingSuggestionProviding {
        let suggestions: [String]

        func suggestions(for word: String, language: LanguageID) -> [String] {
            suggestions
        }
    }

    private final class CountingSuggestionProvider: SpellingSuggestionProviding {
        private(set) var callCount = 0
        let result: [String]

        init(result: [String]) {
            self.result = result
        }

        func suggestions(for word: String, language: LanguageID) -> [String] {
            callCount += 1
            return result
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

    @Test func curatedProviderPrependsRussianCorrectionsAndDeduplicatesDownstream() {
        let provider = CuratedSpellingSuggestionProvider(
            downstream: FakeSuggestionProvider(suggestions: ["Заключил", "Залучил"]),
            curated: [.ru: ["закулчил": ["заключил"]]]
        )

        #expect(provider.suggestions(for: "Закулчил", language: .ru) == ["заключил", "Залучил"])
    }

    @Test func curatedCorrectionsParserReadsLanguageKeyedEntries() {
        let table = CuratedCorrections.parse(
            "# comment\nru заклучил заключил\nru закулчил заключил\n"
        )

        #expect(table?[.ru]?["заклучил"] == ["заключил"])
        #expect(table?[.ru]?["закулчил"] == ["заключил"])
    }

    @Test func curatedCorrectionsParserIgnoresCommentsAndBlankLines() {
        #expect(CuratedCorrections.parse("# only a comment\n\n  \n") == nil)
    }

    @Test func curatedCorrectionsEmbeddedFallbackCoversKnownTypos() {
        #expect(CuratedCorrections.embedded[.ru]?["заклучил"] == ["заключил"])
    }

    @Test func cachedProviderMemoizesGuessesPerWordAndLanguage() {
        let downstream = CountingSuggestionProvider(result: ["book"])
        let provider = CachedSpellingSuggestionProvider(downstream: downstream, capacity: 100)

        #expect(provider.suggestions(for: "bokk", language: .en) == ["book"])
        #expect(provider.suggestions(for: "bokk", language: .en) == ["book"])
        #expect(downstream.callCount == 1) // second identical query served from cache

        _ = provider.suggestions(for: "bokk", language: .ru)
        #expect(downstream.callCount == 2) // different language is a distinct key
    }
}
