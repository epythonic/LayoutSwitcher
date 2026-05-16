import Foundation

/// Tunable numeric limits governing detector confidence and token eligibility.
struct DetectionThresholds: Sendable {
    var minWordLength: Int = 3
    var maxWordLength: Int = 30
    /// Minimum token length eligible for strict dictionary-only short-word correction.
    var shortWordStrictMinLength: Int = 2
    /// Minimum gap between ngram scores of two languages required for an automatic switch.
    var nGramMargin: Double = 0.5
    /// Extra margin required to override a dictionary hit in the active layout.
    var activeDictionaryOverrideMargin: Double = 0.75
    /// Minimum token length before NaturalLanguage tie-breaks are considered.
    var naturalLanguageMinWordLength: Int = 5
    /// Minimum NaturalLanguage probability needed before it can break a tie.
    var naturalLanguageMinimumConfidence: Double = 0.45
    /// Minimum NaturalLanguage probability gap required between two candidates.
    var naturalLanguageTieBreakMargin: Double = 0.15
    /// Minimum corrected length for accidental duplicate-letter correction.
    var duplicateLetterMinCorrectedLength: Int = 4
    /// Minimum n-gram score gain required before dropping a repeated letter.
    var duplicateLetterScoreMargin: Double = 0.05
    /// Minimum token length eligible for two-leading-uppercase correction.
    var doubleCapitalMinLength: Int = 3
    /// Minimum token length eligible for Cupertino-style spelling correction.
    var cupertinoMinLength: Int = 3
    /// Maximum edit distance accepted for Cupertino-style spelling correction.
    var cupertinoMaxEditDistance: Int = 2
    /// Minimum n-gram score gain required before accepting a spelling suggestion.
    var cupertinoScoreMargin: Double = 0.05

    /// Baseline thresholds used when no explicit sensitivity override is set.
    nonisolated static let `default` = DetectionThresholds()
}

/// User-facing detector aggressiveness presets.
enum DetectionSensitivity: String, CaseIterable, Sendable {
    case conservative
    case balanced
    case aggressive

    /// Localized title shown in settings picker.
    var localizedTitle: String {
        switch self {
        case .conservative: String(localized: "sensitivity.conservative")
        case .balanced: String(localized: "sensitivity.balanced")
        case .aggressive: String(localized: "sensitivity.aggressive")
        }
    }

    /// Threshold values associated with this sensitivity preset.
    var thresholds: DetectionThresholds {
        switch self {
        case .conservative:
            DetectionThresholds(nGramMargin: 0.8, activeDictionaryOverrideMargin: 1.0)
        case .balanced:
            .default
        case .aggressive:
            DetectionThresholds(nGramMargin: 0.25, activeDictionaryOverrideMargin: 0.5)
        }
    }
}
