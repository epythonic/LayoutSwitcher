import Foundation

/// Corrects accidental two-leading-uppercase words inside the active language.
@MainActor
struct DoubleCapitalCorrector {
    /// Returns a same-language correction such as `HEllo` -> `Hello`.
    func correction(
        for raw: String,
        dictionary: any WordDictionary,
        thresholds: DetectionThresholds
    ) -> String? {
        guard raw.count <= thresholds.maxWordLength,
              raw.count >= thresholds.doubleCapitalMinLength,
              raw.allSatisfy(\.isLetter),
              raw.uppercased() != raw else {
            return nil
        }

        let characters = Array(raw)
        guard characters.count >= 3,
              characters[0].isUppercase,
              characters[1].isUppercase,
              characters[2].isLowercase else {
            return nil
        }

        let corrected = String(characters[0]) + characters[1].lowercased() + String(characters.dropFirst(2))
        guard corrected != raw, dictionary.contains(corrected) else {
            return nil
        }
        return corrected
    }
}
