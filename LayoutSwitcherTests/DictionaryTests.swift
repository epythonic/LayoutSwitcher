import Testing
@testable import LayoutSwitcher

@MainActor
struct DictionaryTests {
    @Test func englishContainsCommonWords() {
        let dict = EmbeddedDictionaries.english()
        #expect(dict.contains("hello"))
        #expect(dict.contains("Hello"))
        #expect(dict.contains("WORLD"))
        #expect(!dict.contains("ghbdtn"))
    }

    @Test func russianContainsCommonWords() {
        let dict = EmbeddedDictionaries.russian()
        #expect(dict.contains("привет"))
        #expect(dict.contains("Привет"))
        #expect(dict.contains("ПРИВЕТ"))
        #expect(!dict.contains("hello"))
    }

    @Test func ukrainianContainsCommonWords() {
        let dict = EmbeddedDictionaries.ukrainian()
        #expect(dict.contains("привіт"))
        #expect(dict.contains("Привіт"))
        #expect(dict.contains("ПРИВІТ"))
        #expect(!dict.contains("hello"))
    }

    @Test func yoYeNormalization() {
        let dict = InMemoryDictionary(language: .ru, words: ["ёж"])
        #expect(dict.contains("ёж"))
        #expect(dict.contains("еж"))
    }

    @Test func sizeIsPositive() {
        #expect(EmbeddedDictionaries.english().size > 50)
        #expect(EmbeddedDictionaries.russian().size > 50)
        #expect(EmbeddedDictionaries.ukrainian().size > 50)
    }

    @Test func embeddedDictionariesReturnStableValuesPerLanguage() {
        let firstEnglish = EmbeddedDictionaries.english()
        let secondEnglish = EmbeddedDictionaries.english()
        let firstRussian = EmbeddedDictionaries.russian()
        let secondRussian = EmbeddedDictionaries.russian()
        let firstUkrainian = EmbeddedDictionaries.ukrainian()
        let secondUkrainian = EmbeddedDictionaries.ukrainian()
        let firstRomanian = EmbeddedDictionaries.romanian()
        let secondRomanian = EmbeddedDictionaries.romanian()

        #expect(firstEnglish.size == secondEnglish.size)
        #expect(firstRussian.size == secondRussian.size)
        #expect(firstUkrainian.size == secondUkrainian.size)
        #expect(firstRomanian.size == secondRomanian.size)
        #expect(secondEnglish.contains("hello"))
        #expect(secondRussian.contains("привет"))
        #expect(secondUkrainian.contains("привіт"))
        #expect(secondRomanian.contains("bună"))
    }

    @Test func bundledFallbacksProvideExpectedWordsPerLanguage() {
        let english = BundledDictionaryLoader.loadOrEmbedded(language: .en)
        let russian = BundledDictionaryLoader.loadOrEmbedded(language: .ru)
        let ukrainian = BundledDictionaryLoader.loadOrEmbedded(language: .uk)
        let romanian = BundledDictionaryLoader.loadOrEmbedded(language: .ro)

        #expect(english.contains("hello"))
        #expect(russian.contains("привет"))
        #expect(ukrainian.contains("привіт"))
        #expect(romanian.contains("bună"))
        #expect(english.size > 50)
        #expect(russian.size > 50)
    }

    @Test func lazyEmbeddedDictionaryDefersAndMemoizesBuild() {
        var builds = 0
        let dict = LazyEmbeddedDictionary(language: .en) {
            builds += 1
            return InMemoryDictionary(language: .en, words: ["book"])
        }

        #expect(builds == 0)            // construction must not parse anything
        #expect(dict.contains("book"))  // first lookup triggers the build
        #expect(!dict.contains("ghbdtn"))
        #expect(builds == 1)            // built once, then memoized
    }
}
