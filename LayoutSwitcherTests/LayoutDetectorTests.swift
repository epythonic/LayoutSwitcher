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
        romanianDiacriticResolver: RomanianDiacriticResolver(words: EmbeddedDictionaries.romanian().allWords),
        russianYoResolver: RussianYoResolver(words: ["ёжик", "все", "всё"]),
        thresholds: .default
    )

    private func chars(_ keyCodes: [CGKeyCode]) -> [WordChar] {
        keyCodes.map { WordChar(keyCode: $0, unicode: "", flags: [], timestamp: 0) }
    }

    private func chars(_ text: String, language: LanguageID) -> [WordChar] {
        let mapping = RuEnQwertyMapping()
        var result: [WordChar] = []
        result.reserveCapacity(text.count)
        for character in text {
            guard let encoded = mapping.keyCode(for: character, language: language) else {
                Issue.record("missing keyCode for \(character) in \(language.rawValue)")
                continue
            }
            var flags: CGEventFlags = []
            if encoded.shift {
                flags.insert(.maskShift)
            }
            result.append(WordChar(keyCode: encoded.keyCode, unicode: "", flags: flags, timestamp: 0))
        }
        return result
    }

    private func userDictionary(_ language: LanguageID, name: String = #function) -> UserDictionary {
        let url = URL(fileURLWithPath: "/tmp/LayoutSwitcherTests-\(name)-\(language.rawValue).json")
        return UserDictionary(
            language: language,
            storageURL: url,
            createDirectory: { _ in },
            fileExists: { _ in false },
            readData: { _ in Data() },
            writeData: { _, _ in }
        )
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

    @Test func hellooOnEnDropsAccidentalDuplicateLetterWhenEnabled() {
        let buffer = chars("helloo", language: .en)
        let decision = detector.decide(
            buffer: buffer,
            activeLanguage: .en,
            correctDuplicateLetters: true
        )
        #expect(decision == .switchAndRetype(corrected: "hello", target: .en))
    }

    @Test func mixedDoubleCapitalAndDuplicateLetterComposeWhenEnabled() {
        let buffer = chars("HElloo", language: .en)
        let decision = detector.decide(
            buffer: buffer,
            activeLanguage: .en,
            correctDoubleCapitals: true,
            correctDuplicateLetters: true
        )
        #expect(decision == .switchAndRetype(corrected: "Hello", target: .en))
    }

    @Test func пприветOnRuDropsAccidentalLeadingDuplicateLetterWhenEnabled() {
        let buffer = chars("ппривет", language: .ru)
        let decision = detector.decide(
            buffer: buffer,
            activeLanguage: .ru,
            correctDuplicateLetters: true
        )
        #expect(decision == .switchAndRetype(corrected: "привет", target: .ru))
    }

    @Test func привветOnRuDropsAccidentalInternalDuplicateLetterWhenEnabled() {
        let buffer = chars("приввет", language: .ru)
        let decision = detector.decide(
            buffer: buffer,
            activeLanguage: .ru,
            correctDuplicateLetters: true
        )
        #expect(decision == .switchAndRetype(corrected: "привет", target: .ru))
    }

    @Test func cupertinoCorrectsCommonEnglishTypoWhenEnabled() {
        let detector = LayoutDetector(
            mapping: RuEnQwertyMapping(),
            dictionaries: [
                .en: InMemoryDictionary(language: .en, words: ["book"])
            ],
            ngrams: [
                .en: NGramModels.english()
            ],
            spellingSuggestionProvider: FixedSuggestionProvider(suggestionsByWord: ["bokk": ["book"]]),
            thresholds: .default
        )
        let decision = detector.decide(
            buffer: chars("bokk", language: .en),
            activeLanguage: .en,
            correctCommonTypos: true
        )

        #expect(decision == .switchAndRetype(corrected: "book", target: .en))
        #expect(decision.retypePayload?.kind == .cupertino)
    }

    @Test func cupertinoFallsBackWhenDictionaryLacksSuggestionCandidate() {
        let detector = LayoutDetector(
            mapping: RuEnQwertyMapping(),
            dictionaries: [
                .en: InMemoryDictionary(language: .en, words: ["bokk"]),
                .ru: InMemoryDictionary(language: .ru, words: []),
                .uk: InMemoryDictionary(language: .uk, words: []),
                .ro: InMemoryDictionary(language: .ro, words: [])
            ],
            ngrams: [
                .en: NGramModels.english(),
                .ru: NGramModels.russian(),
                .uk: NGramModels.ukrainian(),
                .ro: NGramModels.romanian()
            ],
            spellingSuggestionProvider: FixedSuggestionProvider(suggestionsByWord: ["bokk": ["book"]]),
            languageScorer: FixedTextScoreScorer(scores: ["bokk": -1.0, "book": 1.0]),
            thresholds: DetectionThresholds(cupertinoScoreMargin: 0.0)
        )
        let decision = detector.decide(
            buffer: chars("bokk", language: .en),
            activeLanguage: .en,
            correctCommonTypos: true
        )

        #expect(decision == .switchAndRetype(corrected: "book", target: .en))
    }

    @Test func cupertinoKeepsCommonTypoWhenDisabled() {
        let detector = LayoutDetector(
            mapping: RuEnQwertyMapping(),
            dictionaries: [
                .en: InMemoryDictionary(language: .en, words: ["book"])
            ],
            ngrams: [
                .en: NGramModels.english()
            ],
            spellingSuggestionProvider: FixedSuggestionProvider(suggestionsByWord: ["bokk": ["book"]]),
            thresholds: .default
        )
        let decision = detector.decide(
            buffer: chars("bokk", language: .en),
            activeLanguage: .en,
            correctCommonTypos: false
        )

        #expect(decision == .keep)
    }

    @Test func cupertinoCorrectsRussianTypoWhenActiveDictionaryAlreadyHasMatch() {
        let detector = LayoutDetector(
            mapping: RuEnQwertyMapping(),
            dictionaries: [
                .en: EmbeddedDictionaries.english(),
                .ru: InMemoryDictionary(language: .ru, words: ["привет", "приввет"]),
                .uk: EmbeddedDictionaries.ukrainian(),
                .ro: EmbeddedDictionaries.romanian()
            ],
            ngrams: [
                .en: NGramModels.english(),
                .ru: NGramModels.russian(),
                .uk: NGramModels.ukrainian(),
                .ro: NGramModels.romanian()
            ],
            spellingSuggestionProvider: FixedSuggestionProvider(suggestionsByWord: ["приввет": ["привет"]]),
            thresholds: .default
        )
        let decision = detector.decide(
            buffer: chars("приввет", language: .ru),
            activeLanguage: .ru,
            correctCommonTypos: true
        )

        #expect(decision == .switchAndRetypeWithFeedback(corrected: "привет", target: .ru, kind: .cupertino))
    }

    @Test func cupertinoCorrectsRomanianTypoWhenActiveDictionaryAlreadyHasMatch() {
        let detector = LayoutDetector(
            mapping: RuEnQwertyMapping(),
            dictionaries: [
                .en: EmbeddedDictionaries.english(),
                .ru: EmbeddedDictionaries.russian(),
                .uk: EmbeddedDictionaries.ukrainian(),
                .ro: InMemoryDictionary(language: .ro, words: ["bună", "bunaa"])
            ],
            ngrams: [
                .en: NGramModels.english(),
                .ru: NGramModels.russian(),
                .uk: NGramModels.ukrainian(),
                .ro: NGramModels.romanian()
            ],
            spellingSuggestionProvider: FixedSuggestionProvider(suggestionsByWord: ["bunaa": ["bună"]]),
            thresholds: DetectionThresholds(cupertinoScoreMargin: 0.0)
        )
        let decision = detector.decide(
            buffer: chars("bunaa", language: .ro),
            activeLanguage: .ro,
            correctCommonTypos: true
        )

        #expect(decision == .switchAndRetypeWithFeedback(corrected: "bună", target: .ro, kind: .cupertino))
    }

    @Test func cupertinoDoesNotOverrideWrongLayoutSwitch() {
        let detector = LayoutDetector(
            mapping: RuEnQwertyMapping(),
            dictionaries: [
                .en: InMemoryDictionary(language: .en, words: ["garden"]),
                .ru: InMemoryDictionary(language: .ru, words: ["привет"])
            ],
            ngrams: [
                .en: NGramModels.english(),
                .ru: NGramModels.russian()
            ],
            spellingSuggestionProvider: FixedSuggestionProvider(suggestionsByWord: ["ghbdtn": ["garden"]]),
            thresholds: .default
        )
        let decision = detector.decide(
            buffer: chars([5, 4, 11, 2, 17, 45]),
            activeLanguage: .en,
            correctCommonTypos: true
        )

        #expect(decision == .switchAndRetype(corrected: "привет", target: .ru))
        #expect(decision.retypePayload?.kind == .layoutSwitch)
    }

    @Test func doubleLeadingCapitalsAreCorrectedWhenEnabled() {
        let buffer = chars("ПРивет", language: .ru)
        let decision = detector.decide(
            buffer: buffer,
            activeLanguage: .ru,
            correctDoubleCapitals: true
        )
        #expect(decision == .switchAndRetype(corrected: "Привет", target: .ru))
    }

    @Test func russianYoIsAddedWhenUnambiguous() {
        let buffer = chars("ежик", language: .ru)
        let decision = detector.decide(
            buffer: buffer,
            activeLanguage: .ru,
            autoAddRussianYo: true
        )
        #expect(decision == .switchAndRetype(corrected: "ёжик", target: .ru))
    }

    @Test func russianYoPreservesCapitalizedCasing() {
        let buffer = chars("Ежик", language: .ru)
        let decision = detector.decide(
            buffer: buffer,
            activeLanguage: .ru,
            autoAddRussianYo: true
        )
        #expect(decision == .switchAndRetype(corrected: "Ёжик", target: .ru))
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
            userRomanian: userRomanian,
            systemSpellChecker: DeterministicSpellChecker(),
            thresholds: .default
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
            userRomanian: userRomanian,
            systemSpellChecker: DeterministicSpellChecker(),
            thresholds: .default
        )
        userRomanian.add("școală")

        let buffer = chars([1, 8, 31, 0, 37, 0])
        let decision = detector.decide(buffer: buffer, activeLanguage: .ro, autoAddRomanianDiacritics: true)

        #expect(decision == .switchAndRetype(corrected: "școală", target: .ro))
    }

    @Test func romanianDiacriticResolverCacheRebuildsOnlyAfterUserWordsChange() {
        var buildCount = 0
        let cache = RomanianDiacriticResolverCache(
            embeddedWords: ["bună"],
            buildResolver: { words in
                buildCount += 1
                return RomanianDiacriticResolver(words: words)
            }
        )

        #expect(buildCount == 1)
        #expect(cache.resolver(userWords: []).variants(for: "buna") == ["bună"])
        #expect(cache.plainOverrides(userWords: []) == [])
        #expect(cache.resolver(userWords: []).variants(for: "buna") == ["bună"])
        #expect(buildCount == 1)

        #expect(cache.resolver(userWords: ["școală"]).variants(for: "scoala") == ["școală"])
        #expect(cache.plainOverrides(userWords: ["școală"]) == [])
        #expect(cache.resolver(userWords: ["școală"]).variants(for: "scoala") == ["școală"])
        #expect(buildCount == 2)

        #expect(cache.plainOverrides(userWords: ["buna", "școală"]) == ["buna"])
        #expect(buildCount == 3)
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
            userRomanian: userRomanian,
            systemSpellChecker: DeterministicSpellChecker(),
            thresholds: .default
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
            userRomanian: userRomanian,
            systemSpellChecker: DeterministicSpellChecker(),
            thresholds: .default
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

    @Test func singleZOnEnSwitchesEvenWhenActiveLangDictAcceptsAnyLetter() {
        // Reproduces the production-only case: NSSpellChecker accepts every isolated
        // Latin letter as a valid English word, which would otherwise short-circuit
        // strictShortWordDecision and leave the prior word ambiguous in the
        // auto-extend retroactive scan. With correctSingleCharacterWords=true (forced
        // inside that scan) the active-language dictionary guard must be bypassed.
        let permissiveDetector = LayoutDetector(
            mapping: RuEnQwertyMapping(),
            dictionaries: [
                .en: AlwaysTrueDictionary(),
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
            thresholds: .default
        )
        let decision = permissiveDetector.decide(
            buffer: chars([6]),
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

    @Test func legitimateRussianDuplicateLettersAreKeptWhenDuplicateCorrectionEnabled() {
        let ванна = detector.decide(
            buffer: chars("ванна", language: .ru),
            activeLanguage: .ru,
            correctDuplicateLetters: true
        )
        let аккаунт = detector.decide(
            buffer: chars("аккаунт", language: .ru),
            activeLanguage: .ru,
            correctDuplicateLetters: true
        )

        #expect(ванна == .keep)
        #expect(аккаунт == .keep)
    }

    @Test func doubleLeadingCapitalsAreKeptWhenFeatureDisabled() {
        let decision = detector.decide(
            buffer: chars("ПРивет", language: .ru),
            activeLanguage: .ru
        )
        #expect(decision == .keep)
    }

    @Test func allCapsWordIsNotChangedByDoubleCapitalCorrector() {
        let corrector = DoubleCapitalCorrector()
        let correction = corrector.correction(
            for: "USA",
            dictionary: InMemoryDictionary(language: .en, words: ["usa"]),
            thresholds: .default
        )
        #expect(correction == nil)
    }

    @Test func russianYoLeavesAmbiguousPlainWord() {
        let decision = detector.decide(
            buffer: chars("все", language: .ru),
            activeLanguage: .ru,
            autoAddRussianYo: true
        )
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
            ],
            thresholds: .default
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
            ],
            thresholds: .default
        )
        let buffer = chars([4, 14, 37, 37, 31])
        let decision = detector.decide(buffer: buffer, activeLanguage: .en)
        #expect(decision == .keep)
    }

    @Test func thresholdsOverrideChangesNGramFallbackDecision() {
        let detector = LayoutDetector(
            mapping: FixedRenderMapping(renders: [.en: "abcd", .ru: "абвг"]),
            dictionaries: [
                .en: InMemoryDictionary(language: .en, words: []),
                .ru: InMemoryDictionary(language: .ru, words: []),
                .uk: InMemoryDictionary(language: .uk, words: []),
                .ro: InMemoryDictionary(language: .ro, words: [])
            ],
            ngrams: [
                .en: NGramModel(language: .en, corpus: []),
                .ru: NGramModel(language: .ru, corpus: []),
                .uk: NGramModel(language: .uk, corpus: []),
                .ro: NGramModel(language: .ro, corpus: [])
            ],
            languageScorer: FixedScoreScorer(scores: [
                .en: LanguageScore(naturalLanguageProbability: nil, nGramScore: 0.0),
                .ru: LanguageScore(naturalLanguageProbability: nil, nGramScore: 0.3)
            ]),
            thresholds: .default
        )
        let buffer = chars([0, 1, 2, 3])

        #expect(detector.decide(buffer: buffer, activeLanguage: .en) == .keep)
        #expect(detector.decide(
            buffer: buffer,
            activeLanguage: .en,
            thresholds: DetectionSensitivity.aggressive.thresholds
        ) == .switchAndRetype(corrected: "абвг", target: .ru))
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

/// Permissive dictionary stub used to reproduce production behavior where
/// `NSSpellChecker` accepts every isolated Latin letter as a valid English word.
private struct AlwaysTrueDictionary: WordDictionary {
    let language: LanguageID = .en
    func contains(_ word: String) -> Bool { true }
    var size: Int { Int.max }
}

private final class DeterministicSpellChecker: SpellChecking {
    private let knownWordsByLanguage: [String: Set<String>] = [
        "ro": ["tara"]
    ]

    var availableLanguages: [String] { ["en", "ru", "uk", "ro"] }

    func checkSpelling(
        of stringToCheck: String,
        startingAt startingOffset: Int,
        language: String?,
        wrap wrapFlag: Bool,
        inSpellDocumentWithTag tag: Int,
        wordCount: UnsafeMutablePointer<Int>?
    ) -> NSRange {
        let word = stringToCheck.lowercased()
        if let language, knownWordsByLanguage[language]?.contains(word) == true {
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

private struct FixedSuggestionProvider: SpellingSuggestionProviding {
    let suggestionsByWord: [String: [String]]

    func suggestions(for word: String, language: LanguageID) -> [String] {
        suggestionsByWord[word] ?? []
    }
}

private struct FixedRenderMapping: KeyboardMapping {
    let languagePair: LanguagePair = .ruEn
    let renders: [LanguageID: String]

    func transliterate(_ chars: [WordChar], to language: LanguageID) -> String {
        render(chars, in: language)
    }

    func render(_ chars: [WordChar], in language: LanguageID) -> String {
        renders[language] ?? ""
    }

    func keyCode(for character: Character, language: LanguageID) -> (keyCode: CGKeyCode, shift: Bool)? {
        nil
    }

    func convert(_ text: String, from sourceLanguage: LanguageID, to targetLanguage: LanguageID) -> String {
        text
    }
}

private struct FixedScoreScorer: LanguageScoring {
    let scores: [LanguageID: LanguageScore]

    func score(_ text: String, language: LanguageID) -> LanguageScore {
        scores[language] ?? LanguageScore(naturalLanguageProbability: nil, nGramScore: -.infinity)
    }
}

private struct FixedTextScoreScorer: LanguageScoring {
    let scores: [String: Double]

    func score(_ text: String, language: LanguageID) -> LanguageScore {
        let score = scores[text] ?? -1.0
        return LanguageScore(naturalLanguageProbability: nil, nGramScore: score)
    }
}
