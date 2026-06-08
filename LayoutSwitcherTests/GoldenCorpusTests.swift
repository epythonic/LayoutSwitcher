import CoreGraphics
import Testing
@testable import LayoutSwitcher

/// Decision Lab: a curated golden set of (typed text, active layout) → expected
/// decision cases run against the detector. Extend it with real-world examples
/// to measure and lock in detection accuracy over time.
@MainActor
struct GoldenCorpusTests {
    enum Outcome: Sendable, Equatable {
        case keep // keep or ambiguous — no retype payload
        case switchTo(String, LanguageID)
    }

    struct GoldenCase: Sendable {
        let typed: String
        let typedAs: LanguageID
        let active: LanguageID
        let expect: Outcome
    }

    private let detector = LayoutDetector(
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
        romanianDiacriticResolver: RomanianDiacriticResolver(words: EmbeddedDictionaries.romanian().allWords),
        russianYoResolver: RussianYoResolver(words: ["ёжик", "все", "всё"]),
        thresholds: .default
    )

    private func chars(_ text: String, language: LanguageID) -> [WordChar] {
        let mapping = RuEnQwertyMapping()
        return text.compactMap { character in
            guard let encoded = mapping.keyCode(for: character, language: language) else { return nil }
            var flags: CGEventFlags = []
            if encoded.shift { flags.insert(.maskShift) }
            return WordChar(keyCode: encoded.keyCode, unicode: "", flags: flags, timestamp: 0)
        }
    }

    @Test(arguments: [
        GoldenCase(typed: "ghbdtn", typedAs: .en, active: .en, expect: .switchTo("привет", .ru)),
        GoldenCase(typed: "руддщ", typedAs: .ru, active: .ru, expect: .switchTo("hello", .en)),
        GoldenCase(typed: "hello", typedAs: .en, active: .en, expect: .keep),
        GoldenCase(typed: "привет", typedAs: .ru, active: .ru, expect: .keep),
        GoldenCase(typed: "z", typedAs: .en, active: .en, expect: .keep) // too short → ambiguous
    ])
    func goldenDecision(_ goldenCase: GoldenCase) {
        let decision = detector.decide(
            buffer: chars(goldenCase.typed, language: goldenCase.typedAs),
            activeLanguage: goldenCase.active
        )
        switch goldenCase.expect {
        case .keep:
            #expect(decision.retypePayload == nil, "\(goldenCase.typed): expected keep")
        case .switchTo(let text, let language):
            #expect(decision.retypePayload?.corrected == text, "\(goldenCase.typed)")
            #expect(decision.retypePayload?.target == language, "\(goldenCase.typed)")
        }
    }
}
