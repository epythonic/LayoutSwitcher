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
}
