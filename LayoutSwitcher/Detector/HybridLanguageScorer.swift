import Foundation

/// Combines Apple NaturalLanguage probabilities with existing n-gram fallback.
@MainActor
struct HybridLanguageScorer: LanguageScoring {
    let nGramScorer: NGramLanguageScorer
    let naturalLanguageScorer: NaturalLanguageScorer

    init(
        nGramScorer: NGramLanguageScorer,
        naturalLanguageScorer: NaturalLanguageScorer? = nil
    ) {
        self.nGramScorer = nGramScorer
        self.naturalLanguageScorer = naturalLanguageScorer ?? NaturalLanguageScorer()
    }

    func score(_ text: String, language: LanguageID) -> LanguageScore {
        let nGramScore = nGramScorer.score(text, language: language).nGramScore
        return LanguageScore(
            naturalLanguageProbability: naturalLanguageProbability(text, language: language),
            nGramScore: nGramScore
        )
    }

    func naturalLanguageProbability(_ text: String, language: LanguageID) -> Double? {
        naturalLanguageScorer.naturalLanguageProbability(text, language: language)
    }
}
