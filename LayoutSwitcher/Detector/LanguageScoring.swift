import Foundation

/// Scores rendered text for one candidate language.
@MainActor
protocol LanguageScoring {
    func score(_ text: String, language: LanguageID) -> LanguageScore
    func naturalLanguageProbability(_ text: String, language: LanguageID) -> Double?
}

extension LanguageScoring {
    func naturalLanguageProbability(_ text: String, language: LanguageID) -> Double? {
        score(text, language: language).naturalLanguageProbability
    }
}
