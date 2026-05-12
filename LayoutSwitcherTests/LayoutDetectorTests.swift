import Testing
import CoreGraphics
import Foundation
@testable import LayoutSwitcher

@MainActor
struct LayoutDetectorTests {
    // Use embedded dictionaries only — production detector uses NSSpellChecker which
    // may return locale-specific "yes" for cross-language loanwords and produce
    // ambiguous decisions in tests. Embedded dicts give a deterministic baseline.
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

    private func userDictionary(_ language: LanguageID, name: String = UUID().uuidString) -> UserDictionary {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
            .appendingPathComponent("\(name)-\(language.rawValue).json")
        try? FileManager.default.removeItem(at: url)
        return UserDictionary(language: language, storageURL: url)
    }

    // MARK: - Should switch

    @Test func ghbdtnOnEnSwitchesToРусское() {
        // ghbdtn (keyCodes 5,4,11,2,17,45) typed on EN → "привет" in RU.
        let buffer = chars([5, 4, 11, 2, 17, 45])
        let decision = detector.decide(buffer: buffer, activeLanguage: .en)
        #expect(decision == .switchAndRetype(corrected: "привет", target: .ru))
    }

    @Test func руддщOnRuSwitchesToHello() {
        // hello (keyCodes 4,14,37,37,31) typed on RU → "руддщ" → flipped to "hello".
        let buffer = chars([4, 14, 37, 37, 31])
        let decision = detector.decide(buffer: buffer, activeLanguage: .ru)
        #expect(decision == .switchAndRetype(corrected: "hello", target: .en))
    }

    @Test func romanianPlainBunaSwitchesToDiacriticWhenEnabled() {
        let buffer = chars([11, 32, 45, 0])
        let decision = detector.decide(buffer: buffer, activeLanguage: .ro, autoAddRomanianDiacritics: true)
        #expect(decision == .switchAndRetype(corrected: "bună", target: .ro))
    }

    @Test func romanianPlainCasaSwitchesToDiacriticWhenEnabled() {
        let buffer = chars([8, 0, 1, 0])
        let decision = detector.decide(buffer: buffer, activeLanguage: .ro, autoAddRomanianDiacritics: true)
        #expect(decision == .switchAndRetype(corrected: "casă", target: .ro))
    }

    @Test func romanianPlainTaraSwitchesToDiacriticWhenEnabled() {
        let buffer = chars([17, 0, 15, 0])
        let decision = detector.decide(buffer: buffer, activeLanguage: .ro, autoAddRomanianDiacritics: true)
        #expect(decision == .switchAndRetype(corrected: "țară", target: .ro))
    }

    @Test func romanianDiacriticCasingIsPreserved() {
        let buffer = [
            WordChar(keyCode: 11, unicode: "", flags: [.maskShift], timestamp: 0),
            WordChar(keyCode: 32, unicode: "", flags: [], timestamp: 0),
            WordChar(keyCode: 45, unicode: "", flags: [], timestamp: 0),
            WordChar(keyCode: 0, unicode: "", flags: [], timestamp: 0)
        ]
        let decision = detector.decide(buffer: buffer, activeLanguage: .ro, autoAddRomanianDiacritics: true)
        #expect(decision == .switchAndRetype(corrected: "Bună", target: .ro))
    }

    @Test func romanianUserDictionaryFeedsDiacriticResolver() {
        let userEnglish = userDictionary(.en)
        let userRussian = userDictionary(.ru)
        let userUkrainian = userDictionary(.uk)
        let userRomanian = userDictionary(.ro)
        userRomanian.add("școală")
        let detector = LayoutDetector.defaultMultilingual(
            userEnglish: userEnglish,
            userRussian: userRussian,
            userUkrainian: userUkrainian,
            userRomanian: userRomanian
        )

        let buffer = chars([1, 8, 31, 0, 37, 0])
        let decision = detector.decide(buffer: buffer, activeLanguage: .ro, autoAddRomanianDiacritics: true)

        #expect(decision == .switchAndRetype(corrected: "școală", target: .ro))
    }

    @Test func romanianUserDictionaryUpdatesResolverAfterDetectorCreation() {
        let userEnglish = userDictionary(.en)
        let userRussian = userDictionary(.ru)
        let userUkrainian = userDictionary(.uk)
        let userRomanian = userDictionary(.ro)
        let detector = LayoutDetector.defaultMultilingual(
            userEnglish: userEnglish,
            userRussian: userRussian,
            userUkrainian: userUkrainian,
            userRomanian: userRomanian
        )
        userRomanian.add("școală")

        let buffer = chars([1, 8, 31, 0, 37, 0])
        let decision = detector.decide(buffer: buffer, activeLanguage: .ro, autoAddRomanianDiacritics: true)

        #expect(decision == .switchAndRetype(corrected: "școală", target: .ro))
    }

    @Test func romanianPlainUserDictionaryWordSuppressesDiacriticCorrection() {
        let userEnglish = userDictionary(.en)
        let userRussian = userDictionary(.ru)
        let userUkrainian = userDictionary(.uk)
        let userRomanian = userDictionary(.ro)
        userRomanian.add("buna")
        let detector = LayoutDetector.defaultMultilingual(
            userEnglish: userEnglish,
            userRussian: userRussian,
            userUkrainian: userUkrainian,
            userRomanian: userRomanian
        )

        let buffer = chars([11, 32, 45, 0])
        let decision = detector.decide(buffer: buffer, activeLanguage: .ro, autoAddRomanianDiacritics: true)

        #expect(decision == .keep)
    }

    @Test func romanianMultipleDiacriticVariantsAreKept() {
        let userEnglish = userDictionary(.en)
        let userRussian = userDictionary(.ru)
        let userUkrainian = userDictionary(.uk)
        let userRomanian = userDictionary(.ro)
        userRomanian.add("tară")
        let detector = LayoutDetector.defaultMultilingual(
            userEnglish: userEnglish,
            userRussian: userRussian,
            userUkrainian: userUkrainian,
            userRomanian: userRomanian
        )

        let buffer = chars([17, 0, 15, 0])
        let decision = detector.decide(buffer: buffer, activeLanguage: .ro, autoAddRomanianDiacritics: true)

        #expect(decision == .keep)
    }

    // MARK: - Punctuation inside word (bug repro)

    @Test func ntCommaZOnEnSwitchesToTebya() {
        // n t , z (keyCodes 45,17,43,6) typed on EN with intent of "тебя" on RU.
        // Comma keyCode 43 maps to `б`, so `,` must stay inside the word, not split it.
        let buffer = chars([45, 17, 43, 6])
        let decision = detector.decide(buffer: buffer, activeLanguage: .en)
        #expect(decision == .switchAndRetype(corrected: "тебя", target: .ru))
    }

    @Test func eSemicolonTOnEnSwitchesToUzhe() {
        // e ; t (keyCodes 14,41,17) typed on EN with intent of "уже" on RU.
        // Semicolon keyCode 41 maps to `ж`.
        let buffer = chars([14, 41, 17])
        let decision = detector.decide(buffer: buffer, activeLanguage: .en)
        #expect(decision == .switchAndRetype(corrected: "уже", target: .ru))
    }

    @Test func semicolonLeOnEnSwitchesToZhdu() {
        // ; l e (keyCodes 41,37,14) typed on EN with intent of "жду" on RU.
        let buffer = chars([41, 37, 14])
        let decision = detector.decide(buffer: buffer, activeLanguage: .en)
        #expect(decision == .switchAndRetype(corrected: "жду", target: .ru))
    }

    @Test func jrOnEnSwitchesToOk() {
        // j r (keyCodes 38,15) — 2-char short word that maps to "ок" on RU.
        // Verifies strictShortWordDecision path for length=2 tokens.
        let buffer = chars([38, 15])
        let decision = detector.decide(buffer: buffer, activeLanguage: .en)
        #expect(decision == .switchAndRetype(corrected: "ок", target: .ru))
    }

    @Test func singleZOnEnIsAmbiguousByDefault() {
        // z alone (keyCode 6) — without opt-in, 1-char tokens are too short.
        let buffer = chars([6])
        let decision = detector.decide(buffer: buffer, activeLanguage: .en)
        if case .ambiguous = decision {
            // ok
        } else {
            Issue.record("expected ambiguous for default 1-char, got \(decision)")
        }
    }

    @Test func singleZOnEnSwitchesWhenSingleCharCorrectionEnabled() {
        // z (keyCode 6) → "я" on RU when correctSingleCharacterWords is enabled.
        let buffer = chars([6])
        let decision = detector.decide(
            buffer: buffer,
            activeLanguage: .en,
            correctSingleCharacterWords: true
        )
        #expect(decision == .switchAndRetype(corrected: "я", target: .ru))
    }

    // MARK: - Should keep

    @Test func realEnglishWordIsKept() {
        // hello typed on EN — keep.
        let buffer = chars([4, 14, 37, 37, 31])
        let decision = detector.decide(buffer: buffer, activeLanguage: .en)
        #expect(decision == .keep)
    }

    @Test func realRussianWordIsKept() {
        // привет typed on RU — keep.
        let buffer = chars([5, 4, 11, 2, 17, 45])
        let decision = detector.decide(buffer: buffer, activeLanguage: .ru)
        #expect(decision == .keep)
    }

    @Test func realUkrainianWordIsKept() {
        // привіт typed on UK — keep.
        let buffer = chars([5, 4, 11, 2, 1, 45])
        let decision = detector.decide(buffer: buffer, activeLanguage: .uk)
        #expect(decision == .keep)
    }

    @Test func romanianPlainBunaIsKeptWhenDiacriticsDisabled() {
        let buffer = chars([11, 32, 45, 0])
        let decision = detector.decide(buffer: buffer, activeLanguage: .ro)
        #expect(decision == .keep)
    }

    @Test func activeDictionaryHitCanBeOverriddenByStrongWrongLayoutCandidate() {
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
            ]
        )
        let buffer = chars([5, 4, 11, 2, 17, 45])
        let decision = detector.decide(buffer: buffer, activeLanguage: .en)
        #expect(decision == .switchAndRetype(corrected: "привет", target: .ru))
    }

    @Test func activeDictionaryHitKeepsWhenCompetingCandidateIsWeak() {
        let detector = LayoutDetector(
            mapping: RuEnQwertyMapping(),
            dictionaries: [
                .en: EmbeddedDictionaries.english(),
                .ru: InMemoryDictionary(language: .ru, words: ["руддщ"]),
                .uk: EmbeddedDictionaries.ukrainian(),
                .ro: EmbeddedDictionaries.romanian()
            ],
            ngrams: [
                .en: NGramModels.english(),
                .ru: NGramModels.russian(),
                .uk: NGramModels.ukrainian(),
                .ro: NGramModels.romanian()
            ]
        )
        let buffer = chars([4, 14, 37, 37, 31])
        let decision = detector.decide(buffer: buffer, activeLanguage: .en)
        #expect(decision == .keep)
    }

    // MARK: - Ambiguous

    @Test func tooShortIsAmbiguous() {
        let buffer = chars([4, 11]) // 2 chars
        let decision = detector.decide(buffer: buffer, activeLanguage: .en)
        if case .ambiguous = decision {
            // ok
        } else {
            Issue.record("expected ambiguous, got \(decision)")
        }
    }
}
