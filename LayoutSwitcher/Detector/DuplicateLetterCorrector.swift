import Foundation

/// Detects accidental adjacent duplicate letters within the active language.
///
/// This corrector only proposes a same-language edit when the original token is
/// not already a known word and dropping the second repeated letter produces one
/// clear dictionary-backed candidate.
@MainActor
struct DuplicateLetterCorrector {
    /// Accepted same-language correction.
    struct Correction: Equatable, Sendable {
        /// Text after removing one accidental repeated letter.
        let corrected: String
        /// N-gram score improvement over the original token.
        let scoreGain: Double
    }

    /// Returns a conservative correction for one active-language token.
    func correction(
        for raw: String,
        language: LanguageID,
        dictionary: any WordDictionary,
        scorer: any LanguageScoring,
        thresholds: DetectionThresholds
    ) -> Correction? {
        guard raw.count <= thresholds.maxWordLength,
              raw.allSatisfy(\.isLetter),
              dictionary.contains(raw) == false else {
            return nil
        }

        let validCandidates = Self.dropSecondDuplicateCandidates(for: raw)
            .filter { candidate in
                candidate.count >= thresholds.duplicateLetterMinCorrectedLength
                    && dictionary.contains(candidate)
            }
        let uniqueCandidates = Self.uniqueByNormalizedForm(validCandidates)
        guard uniqueCandidates.count == 1, let corrected = uniqueCandidates.first else {
            return nil
        }

        let rawScore = scorer.score(raw, language: language).nGramScore
        let correctedScore = scorer.score(corrected, language: language).nGramScore
        let scoreGain = correctedScore - rawScore
        guard scoreGain >= thresholds.duplicateLetterScoreMargin else {
            return nil
        }
        return Correction(corrected: corrected, scoreGain: scoreGain)
    }

    /// Builds candidates by removing the second character from every adjacent
    /// repeated letter pair. The original casing of the first letter is kept.
    private static func dropSecondDuplicateCandidates(for word: String) -> [String] {
        let characters = Array(word)
        guard characters.count >= 2 else { return [] }

        var candidates: [String] = []
        for index in 0..<(characters.count - 1) {
            let current = characters[index]
            let next = characters[index + 1]
            guard current.isLetter,
                  next.isLetter,
                  String(current).lowercased() == String(next).lowercased() else {
                continue
            }
            var candidate = characters
            candidate.remove(at: index + 1)
            candidates.append(String(candidate))
        }
        return candidates
    }

    private static func uniqueByNormalizedForm(_ candidates: [String]) -> [String] {
        var byNormalizedForm: [String: String] = [:]
        for candidate in candidates {
            let normalized = InMemoryDictionary.normalize(candidate)
            if byNormalizedForm[normalized] == nil {
                byNormalizedForm[normalized] = candidate
            }
        }
        return Array(byNormalizedForm.values)
    }
}
