import Foundation

/// Breakdown of language confidence signals kept on separate scales.
struct LanguageScore: Equatable, Sendable {
    /// Probability-like score from Apple's NaturalLanguage framework, when usable.
    let naturalLanguageProbability: Double?
    /// Existing character n-gram score, used as fallback and for numeric margins.
    let nGramScore: Double
}
