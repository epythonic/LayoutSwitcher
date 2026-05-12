import Foundation

/// Wraps existing n-gram models in the language scoring abstraction.
@MainActor
struct NGramLanguageScorer: LanguageScoring {
    let ngrams: [LanguageID: NGramModel]

    func score(_ text: String, language: LanguageID) -> LanguageScore {
        LanguageScore(
            naturalLanguageProbability: nil,
            nGramScore: ngrams[language]?.score(text) ?? -.infinity
        )
    }
}
