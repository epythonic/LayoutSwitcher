import Foundation

/// Per-language alphabet/character classification helpers for the detector.
/// Pure: depend only on the input word and language tag, no detector state.
extension LayoutDetector {
    /// Validates that word characters belong to the alphabet expected for the
    /// given language. Used to filter out cross-script noise (e.g. a Latin
    /// word can never legitimately be Russian).
    func wordMatchesAlphabet(_ word: String, of language: LanguageID) -> Bool {
        let scalars = word.unicodeScalars
        switch language {
        case .en:
            return scalars.allSatisfy { $0.value < 128 && Character($0).isLetter }
        case .ru:
            let lower = word.lowercased()
            return lower.unicodeScalars.allSatisfy { scalar in
                let v = scalar.value
                return (v >= 0x0400 && v <= 0x04FF) || scalar == "ё"
            }
        case .uk:
            return word.lowercased().unicodeScalars.allSatisfy { scalar in
                let v = scalar.value
                return (v >= 0x0400 && v <= 0x04FF) || ["і", "ї", "є", "ґ"].contains(scalar)
            }
        case .ro:
            return scalars.allSatisfy { scalar in
                if scalar.value < 128, Character(scalar).isLetter { return true }
                let extras: Set<Unicode.Scalar> = ["ă", "â", "î", "ș", "ț", "Ă", "Â", "Î", "Ș", "Ț"]
                return extras.contains(scalar)
            }
        }
    }

    /// Distinguishes a real language-specific candidate from an ASCII loanword
    /// accepted by a permissive system spell-check dictionary. Returns true
    /// only if the text contains a glyph unique to the named language.
    func hasLanguageSpecificCharacters(_ text: String, of language: LanguageID) -> Bool {
        switch language {
        case .en:
            return true
        case .ru, .uk:
            return text.unicodeScalars.contains { scalar in
                let value = scalar.value
                return (value >= 0x0400 && value <= 0x04FF) || scalar == "ё"
            }
        case .ro:
            return RomanianDiacriticResolver.containsRomanianDiacritic(text)
        }
    }
}
