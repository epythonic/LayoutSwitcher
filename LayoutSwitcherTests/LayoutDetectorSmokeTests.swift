import Testing
import CoreGraphics
import Foundation
@testable import LayoutSwitcher

/// Smoke tests for `LayoutDetector` using embedded dictionaries to guarantee
/// deterministic, cross-machine identical decisions.
@MainActor
struct LayoutDetectorSmokeTests {

    let detector = LayoutDetector(
        mapping: RuEnQwertyMapping(),
        dictionaries: [
            .en: EmbeddedDictionaries.english(),
            .ru: EmbeddedDictionaries.russian(),
            .uk: EmbeddedDictionaries.ukrainian(),
            .ro: EmbeddedDictionaries.romanian()
        ],
        ngrams: [
            .en: NGramModels.english(),
            .ru: NGramModels.russian(),
            .uk: NGramModels.ukrainian(),
            .ro: NGramModels.romanian()
        ],
        romanianDiacriticResolver: RomanianDiacriticResolver(words: EmbeddedDictionaries.romanian().allWords)
    )

    private func chars(_ keyCodes: [CGKeyCode]) -> [WordChar] {
        keyCodes.map { WordChar(keyCode: $0, unicode: "", flags: [], timestamp: 0) }
    }

    // MARK: - Cross-language switches

    @Test func russianHelloOnEnSwitchesToRu() {
        // ghbdtn → привет
        let decision = detector.decide(buffer: chars([5, 4, 11, 2, 17, 45]), activeLanguage: .en)
        #expect(decision == .switchAndRetype(corrected: "привет", target: .ru))
    }

    @Test func englishHelloOnRuSwitchesToEn() {
        // hello (keycodes typed on RU layout)
        let decision = detector.decide(buffer: chars([4, 14, 37, 37, 31]), activeLanguage: .ru)
        #expect(decision == .switchAndRetype(corrected: "hello", target: .en))
    }

    // MARK: - Keep decisions

    @Test func englishWordOnEnIsKept() {
        let decision = detector.decide(buffer: chars([8, 14, 15, 15, 31]), activeLanguage: .en)
        // "hello" typed on EN layout should stay EN (dict hit in active language)
        #expect(decision == .keep)
    }

    // MARK: - Romanian diacritics

    @Test func romanianPlainBunaAddsDiacriticWhenEnabled() {
        let decision = detector.decide(
            buffer: chars([11, 32, 45, 0]),
            activeLanguage: .ro,
            autoAddRomanianDiacritics: true
        )
        #expect(decision == .switchAndRetype(corrected: "bună", target: .ro))
    }

    @Test func romanianPlainBunaIsKeptWhenDisabled() {
        let decision = detector.decide(
            buffer: chars([11, 32, 45, 0]),
            activeLanguage: .ro,
            autoAddRomanianDiacritics: false
        )
        #expect(decision == .keep)
    }

    // MARK: - Ambiguous / edge cases

    @Test func tooShortIsAmbiguous() {
        let decision = detector.decide(buffer: chars([1, 2]), activeLanguage: .en)
        if case .ambiguous = decision {
            // expected
        } else {
            Issue.record("Expected ambiguous, got \(String(describing: decision))")
        }
    }

    @Test func nonLettersIsAmbiguous() {
        // Keycodes 18=1 (digit), 1=s, 2=d — includes non-letter content
        let decision = detector.decide(buffer: chars([18, 1, 2]), activeLanguage: .en)
        if case .ambiguous = decision {
            // expected
        } else {
            Issue.record("Expected ambiguous, got \(String(describing: decision))")
        }
    }
}
