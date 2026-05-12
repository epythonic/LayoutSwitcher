import Foundation
import NaturalLanguage

/// Uses Apple's NaturalLanguage recognizer as an optional tie-break signal.
@MainActor
struct NaturalLanguageScorer: LanguageScoring {
    let minimumTextLength: Int
    let maximumHypotheses: Int

    init(
        minimumTextLength: Int = DetectionThresholds.default.naturalLanguageMinWordLength,
        maximumHypotheses: Int = LanguageID.allCases.count
    ) {
        self.minimumTextLength = minimumTextLength
        self.maximumHypotheses = maximumHypotheses
    }

    func score(_ text: String, language: LanguageID) -> LanguageScore {
        LanguageScore(
            naturalLanguageProbability: naturalLanguageProbability(text, language: language),
            nGramScore: 0
        )
    }

    func naturalLanguageProbability(_ text: String, language: LanguageID) -> Double? {
        guard text.count >= minimumTextLength,
              let nlLanguage = language.naturalLanguageIdentifier else {
            return nil
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.languageHypotheses(withMaximum: maximumHypotheses)[nlLanguage]
    }
}

private extension LanguageID {
    var naturalLanguageIdentifier: NLLanguage? {
        switch self {
        case .en:
            return .english
        case .ru:
            return .russian
        case .uk:
            return .ukrainian
        case .ro:
            return .romanian
        }
    }
}
