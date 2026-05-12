import CoreGraphics
import Testing
@testable import LayoutSwitcher

@MainActor
struct SelectionTextConverterTests {
    private struct StubMapping: KeyboardMapping {
        let languagePair: LanguagePair = .ruEn

        func transliterate(_ chars: [WordChar], to language: LanguageID) -> String {
            chars.map(\.unicode).joined()
        }
        func render(_ chars: [WordChar], in language: LanguageID) -> String {
            chars.map(\.unicode).joined()
        }
        func keyCode(for character: Character, language: LanguageID) -> (keyCode: CGKeyCode, shift: Bool)? {
            nil
        }
        func convert(_ text: String, from sourceLanguage: LanguageID, to targetLanguage: LanguageID) -> String {
            text.uppercased()
        }
    }

    @Test func convertAppliesMapping() {
        let converter = SelectionTextConverter(mapping: StubMapping())
        let result = converter.convert("hello")
        #expect(result == "HELLO")
    }

    @Test func maxSelectionLengthClampsLongText() {
        let converter = SelectionTextConverter(mapping: StubMapping(), maxSelectionLength: 5)
        let longText = String(repeating: "a", count: 200)
        let result = converter.convert(longText)
        #expect(result.count == 100)
    }

    @Test func defaultMaxSelectionLengthIsSane() {
        #expect(SelectionTextConverter.defaultMaxSelectionLength > 100)
        #expect(SelectionTextConverter.absoluteMaxSelectionLength > SelectionTextConverter.defaultMaxSelectionLength)
    }

    @Test func clampedMaxRespectsBounds() {
        #expect(SelectionTextConverter.clampedMaxSelectionLength(0) == 100)
        #expect(SelectionTextConverter.clampedMaxSelectionLength(999_999) == SelectionTextConverter.absoluteMaxSelectionLength)
        #expect(SelectionTextConverter.clampedMaxSelectionLength(500) == 500)
    }

    @Test func detectsCyrillicAsRussianSource() {
        struct CyrillicMapping: KeyboardMapping {
            let languagePair: LanguagePair = .ruEn
            func transliterate(_ chars: [WordChar], to language: LanguageID) -> String { "" }
            func render(_ chars: [WordChar], in language: LanguageID) -> String { "" }
            func keyCode(for character: Character, language: LanguageID) -> (keyCode: CGKeyCode, shift: Bool)? { nil }
            func convert(_ text: String, from sourceLanguage: LanguageID, to targetLanguage: LanguageID) -> String {
                if sourceLanguage == .ru && targetLanguage == .en { return "en:\(text)" }
                if sourceLanguage == .en && targetLanguage == .ru { return "ru:\(text)" }
                return text
            }
        }
        let converter = SelectionTextConverter(mapping: CyrillicMapping())
        let result = converter.convert("привет")
        #expect(result == "en:привет")
    }

    @Test func detectsLatinAsEnglishSource() {
        struct LatinMapping: KeyboardMapping {
            let languagePair: LanguagePair = .ruEn
            func transliterate(_ chars: [WordChar], to language: LanguageID) -> String { "" }
            func render(_ chars: [WordChar], in language: LanguageID) -> String { "" }
            func keyCode(for character: Character, language: LanguageID) -> (keyCode: CGKeyCode, shift: Bool)? { nil }
            func convert(_ text: String, from sourceLanguage: LanguageID, to targetLanguage: LanguageID) -> String {
                "\(sourceLanguage.rawValue)->\(targetLanguage.rawValue):\(text)"
            }
        }
        let converter = SelectionTextConverter(mapping: LatinMapping())
        let result = converter.convert("hello")
        #expect(result == "en->ru:hello")
    }
}
