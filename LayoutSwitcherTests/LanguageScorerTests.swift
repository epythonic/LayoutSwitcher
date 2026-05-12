import CoreGraphics
import Testing
@testable import LayoutSwitcher

@MainActor
struct LanguageScorerTests {
    private struct FixedMapping: KeyboardMapping {
        let renders: [LanguageID: String]
        let languagePair: LanguagePair = .ruEn

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

    private struct StubLanguageScorer: LanguageScoring {
        let scores: [String: [LanguageID: LanguageScore]]

        func score(_ text: String, language: LanguageID) -> LanguageScore {
            let score = scores[text]?[language]
            return LanguageScore(
                naturalLanguageProbability: nil,
                nGramScore: score?.nGramScore ?? -.infinity
            )
        }

        func naturalLanguageProbability(_ text: String, language: LanguageID) -> Double? {
            scores[text]?[language]?.naturalLanguageProbability
        }
    }

    private func chars(_ keyCodes: [CGKeyCode] = [0]) -> [WordChar] {
        keyCodes.map { WordChar(keyCode: $0, unicode: "", flags: [], timestamp: 0) }
    }

    @Test func nGramLanguageScorerReturnsNGramScoreWithoutNaturalLanguageProbability() {
        let scorer = NGramLanguageScorer(ngrams: [.en: NGramModels.english()])

        let score = scorer.score("hello", language: .en)

        #expect(score.naturalLanguageProbability == nil)
        #expect(score.nGramScore == NGramModels.english().score("hello"))
    }

    @Test func naturalLanguageScorerRespectsMinimumTextLength() {
        let scorer = NaturalLanguageScorer(minimumTextLength: 100)

        #expect(scorer.naturalLanguageProbability("hello", language: .en) == nil)
        #expect(scorer.score("hello", language: .en).nGramScore == 0)
    }

    @Test func hybridLanguageScorerKeepsNGramFallbackWhenNaturalLanguageIsUnavailable() {
        let ngrams: [LanguageID: NGramModel] = [.en: NGramModels.english()]
        let scorer = HybridLanguageScorer(
            nGramScorer: NGramLanguageScorer(ngrams: ngrams),
            naturalLanguageScorer: NaturalLanguageScorer(minimumTextLength: 100)
        )

        let score = scorer.score("hello", language: .en)

        #expect(score.naturalLanguageProbability == nil)
        #expect(score.nGramScore == ngrams[.en]?.score("hello"))
    }

    @Test func tieBreakRankPrefersCyrillicThenRomanianThenEnglish() {
        let rank = LayoutDetector.tieBreakRank
        guard let ru = rank[.ru], let uk = rank[.uk], let ro = rank[.ro], let en = rank[.en] else {
            Issue.record("tieBreakRank missing entry")
            return
        }
        #expect(ru < uk)
        #expect(uk < ro)
        #expect(ro < en)
    }

    @Test func naturalLanguageTieBreakPrefersRomanianWhenConfidenceIsClear() {
        let detector = detector(
            renders: [
                .en: "salut",
                .ru: "ыфдге",
                .uk: "іфдпе",
                .ro: "salut"
            ],
            dictionaries: [
                .en: ["salut"],
                .ro: ["salut"]
            ],
            scores: [
                "salut": [
                    .en: LanguageScore(naturalLanguageProbability: 0.10, nGramScore: 0),
                    .ro: LanguageScore(naturalLanguageProbability: 0.80, nGramScore: 0)
                ]
            ]
        )

        let decision = detector.decide(buffer: chars(), activeLanguage: .ru)

        #expect(decision == .switchAndRetype(corrected: "salut", target: .ro))
    }

    @Test func naturalLanguageTieBreakFallsBackToNGramWhenConfidenceIsLow() {
        let detector = detector(
            renders: [
                .en: "salut",
                .ru: "ыфдге",
                .uk: "іфдпе",
                .ro: "salut"
            ],
            dictionaries: [
                .en: ["salut"],
                .ro: ["salut"]
            ],
            scores: [
                "salut": [
                    .en: LanguageScore(naturalLanguageProbability: 0.30, nGramScore: 0.10),
                    .ro: LanguageScore(naturalLanguageProbability: 0.28, nGramScore: 0.80)
                ]
            ]
        )

        let decision = detector.decide(buffer: chars(), activeLanguage: .ru)

        #expect(decision == .switchAndRetype(corrected: "salut", target: .ro))
    }

    @Test func naturalLanguageTieBreakFallsBackToNGramForShortWords() {
        let detector = detector(
            renders: [
                .en: "ana",
                .ru: "фтф",
                .uk: "фтф",
                .ro: "ana"
            ],
            dictionaries: [
                .en: ["ana"],
                .ro: ["ana"]
            ],
            scores: [
                "ana": [
                    .en: LanguageScore(naturalLanguageProbability: 0.10, nGramScore: 0.80),
                    .ro: LanguageScore(naturalLanguageProbability: 0.90, nGramScore: 0.10)
                ]
            ]
        )

        let decision = detector.decide(buffer: chars(), activeLanguage: .ru)

        #expect(decision == .switchAndRetype(corrected: "ana", target: .en))
    }

    @Test func romanianSpecificCandidateStillBeatsEnglishDictionaryHit() {
        let detector = detector(
            renders: [
                .en: "buna",
                .ru: "ифтф",
                .uk: "ифтф",
                .ro: "bună"
            ],
            dictionaries: [
                .en: ["buna"],
                .ro: ["bună"]
            ],
            scores: [
                "buna": [.en: LanguageScore(naturalLanguageProbability: 0.90, nGramScore: 0)],
                "bună": [.ro: LanguageScore(naturalLanguageProbability: 0.10, nGramScore: 0)]
            ]
        )

        let decision = detector.decide(buffer: chars(), activeLanguage: .ru)

        #expect(decision == .switchAndRetype(corrected: "bună", target: .ro))
    }

    private func detector(
        renders: [LanguageID: String],
        dictionaries: [LanguageID: [String]],
        scores: [String: [LanguageID: LanguageScore]]
    ) -> LayoutDetector {
        LayoutDetector(
            mapping: FixedMapping(renders: renders),
            dictionaries: [
                .en: InMemoryDictionary(language: .en, words: dictionaries[.en] ?? []),
                .ru: InMemoryDictionary(language: .ru, words: dictionaries[.ru] ?? []),
                .uk: InMemoryDictionary(language: .uk, words: dictionaries[.uk] ?? []),
                .ro: InMemoryDictionary(language: .ro, words: dictionaries[.ro] ?? [])
            ],
            ngrams: [
                .en: NGramModel(language: .en, corpus: []),
                .ru: NGramModel(language: .ru, corpus: []),
                .uk: NGramModel(language: .uk, corpus: []),
                .ro: NGramModel(language: .ro, corpus: [])
            ],
            languageScorer: StubLanguageScorer(scores: scores)
        )
    }
}
