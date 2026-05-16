import Foundation

/// Corrects conservative same-language spelling mistakes using ordered spell-check suggestions.
@MainActor
struct CupertinoCorrector {
    /// Accepted Cupertino correction.
    struct Correction: Equatable, Sendable {
        /// Suggested same-language spelling.
        let corrected: String
        /// Damerau-Levenshtein edit distance from the original token.
        let editDistance: Int
        /// N-gram score improvement over the original token.
        let scoreGain: Double
    }

    /// Returns a dictionary-backed correction for one misspelled active-language token.
    func correction(
        for raw: String,
        language: LanguageID,
        dictionary: any WordDictionary,
        suggestionProvider: any SpellingSuggestionProviding,
        scorer: any LanguageScoring,
        thresholds: DetectionThresholds
    ) -> Correction? {
        guard raw.count >= thresholds.cupertinoMinLength,
              raw.count <= thresholds.maxWordLength,
              raw.allSatisfy(\.isLetter) else {
            return nil
        }

        let rawNormalized = InMemoryDictionary.normalize(raw)
        let suggestions = suggestionProvider.suggestions(for: raw, language: language)
            .lazy
            .map { Self.applyCasing(of: raw, to: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { candidate in
                !candidate.isEmpty
                    && candidate.count <= thresholds.maxWordLength
                    && candidate.allSatisfy(\.isLetter)
                    && InMemoryDictionary.normalize(candidate) != rawNormalized
                    && Self.wordMatchesAlphabet(candidate, of: language)
            }
            .reduce(into: [String]()) { candidates, candidate in
                let normalized = InMemoryDictionary.normalize(candidate)
                if !candidates.contains(where: { InMemoryDictionary.normalize($0) == normalized }) {
                    candidates.append(candidate)
                }
            }

        let dictionaryValidatedSuggestions = suggestions.filter { dictionary.contains($0) }
        let validSuggestions = dictionaryValidatedSuggestions.isEmpty ? suggestions : dictionaryValidatedSuggestions
        guard let first = validSuggestions.first else { return nil }
        let distance = Self.damerauLevenshteinDistance(raw.lowercased(), first.lowercased())
        guard distance > 0,
              distance <= thresholds.cupertinoMaxEditDistance else {
            return nil
        }

        let rawScore = scorer.score(raw, language: language).nGramScore
        let correctedScore = scorer.score(first, language: language).nGramScore
        let scoreGain = correctedScore - rawScore
        guard scoreGain >= thresholds.cupertinoScoreMargin else {
            return nil
        }
        return Correction(corrected: first, editDistance: distance, scoreGain: scoreGain)
    }

    /// Mirrors common word casing from the original token onto a lowercase suggestion.
    private static func applyCasing(of original: String, to suggestion: String) -> String {
        guard !suggestion.isEmpty else { return suggestion }
        if original.uppercased() == original {
            return suggestion.uppercased()
        }
        guard let firstOriginal = original.first,
              firstOriginal.isUppercase,
              let firstSuggestion = suggestion.first else {
            return suggestion.lowercased()
        }
        return firstSuggestion.uppercased() + suggestion.dropFirst().lowercased()
    }

    /// Filters spell-checker suggestions to the active language script.
    private static func wordMatchesAlphabet(_ word: String, of language: LanguageID) -> Bool {
        let scalars = word.unicodeScalars
        switch language {
        case .en:
            return scalars.allSatisfy { $0.value < 128 && Character($0).isLetter }
        case .ru:
            return word.lowercased().unicodeScalars.allSatisfy { scalar in
                let value = scalar.value
                return (value >= 0x0400 && value <= 0x04FF) || scalar == "ё"
            }
        case .uk:
            return word.lowercased().unicodeScalars.allSatisfy { scalar in
                let value = scalar.value
                return (value >= 0x0400 && value <= 0x04FF) || ["і", "ї", "є", "ґ"].contains(scalar)
            }
        case .ro:
            let extras: Set<Unicode.Scalar> = ["ă", "â", "î", "ș", "ț", "Ă", "Â", "Î", "Ș", "Ț"]
            return scalars.allSatisfy { scalar in
                if scalar.value < 128, Character(scalar).isLetter { return true }
                return extras.contains(scalar)
            }
        }
    }

    /// Computes adjacent-transposition-aware edit distance.
    private static func damerauLevenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let source = Array(lhs)
        let target = Array(rhs)
        if source.isEmpty { return target.count }
        if target.isEmpty { return source.count }

        var distances = Array(
            repeating: Array(repeating: 0, count: target.count + 1),
            count: source.count + 1
        )
        for sourceIndex in 0...source.count {
            distances[sourceIndex][0] = sourceIndex
        }
        for targetIndex in 0...target.count {
            distances[0][targetIndex] = targetIndex
        }

        for sourceIndex in 1...source.count {
            for targetIndex in 1...target.count {
                let cost = source[sourceIndex - 1] == target[targetIndex - 1] ? 0 : 1
                var value = min(
                    distances[sourceIndex - 1][targetIndex] + 1,
                    distances[sourceIndex][targetIndex - 1] + 1,
                    distances[sourceIndex - 1][targetIndex - 1] + cost
                )
                if sourceIndex > 1,
                   targetIndex > 1,
                   source[sourceIndex - 1] == target[targetIndex - 2],
                   source[sourceIndex - 2] == target[targetIndex - 1] {
                    value = min(value, distances[sourceIndex - 2][targetIndex - 2] + 1)
                }
                distances[sourceIndex][targetIndex] = value
            }
        }
        return distances[source.count][target.count]
    }
}
