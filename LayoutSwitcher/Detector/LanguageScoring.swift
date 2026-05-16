import Foundation

/// Scores rendered text for one candidate language.
@MainActor
protocol LanguageScoring {
    /// Returns combined score components for text interpreted as the given language.
    func score(_ text: String, language: LanguageID) -> LanguageScore

    /// Returns optional NaturalLanguage probability when the scorer can provide it.
    func naturalLanguageProbability(_ text: String, language: LanguageID) -> Double?
}

extension LanguageScoring {
    /// Default probability lookup backed by `score(_:language:)`.
    func naturalLanguageProbability(_ text: String, language: LanguageID) -> Double? {
        score(text, language: language).naturalLanguageProbability
    }
}
