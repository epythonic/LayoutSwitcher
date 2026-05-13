import Foundation

/// Expands plain Romanian words into diacritic variants based on known corpora.
struct RomanianDiacriticResolver: Sendable {
    private let variantsByPlain: [String: [String]]

    /// Builds resolver index from words containing valid Romanian diacritics.
    init(words: some Sequence<String>) {
        var buckets: [String: Set<String>] = [:]
        for word in words {
            let normalized = InMemoryDictionary.normalize(word)
            guard Self.containsRomanianDiacritic(normalized) else { continue }
            let plain = Self.plainKey(normalized)
            guard plain != normalized else { continue }
            buckets[plain, default: []].insert(normalized)
        }
        self.variantsByPlain = buckets.mapValues { Array($0).sorted() }
    }

    /// Returns candidate diacritic variants when input word is plain (without diacritics).
    func variants(for word: String) -> [String] {
        let normalized = InMemoryDictionary.normalize(word)
        let plain = Self.plainKey(normalized)
        guard plain == normalized else { return [] }
        let variants = variantsByPlain[plain] ?? []
        return variants.map { Self.matchCasing(of: word, variant: $0) }
    }

    /// Converts Romanian diacritics to plain ASCII surrogate key.
    static func plainKey(_ word: String) -> String {
        var result = ""
        result.reserveCapacity(word.count)
        for scalar in word.lowercased().unicodeScalars {
            switch scalar {
            case "ă", "â": result.append("a")
            case "î": result.append("i")
            case "ș", "ş": result.append("s")
            case "ț", "ţ": result.append("t")
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// Checks whether token includes at least one Romanian-specific diacritic scalar.
    static func containsRomanianDiacritic(_ word: String) -> Bool {
        word.unicodeScalars.contains { scalar in
            switch scalar {
            case "ă", "â", "î", "ș", "ş", "ț", "ţ", "Ă", "Â", "Î", "Ș", "Ş", "Ț", "Ţ":
                return true
            default:
                return false
            }
        }
    }

    /// Aligns output variant casing with original token casing style.
    private static func matchCasing(of original: String, variant: String) -> String {
        if original.uppercased() == original {
            return variant.uppercased()
        }
        guard let first = original.first, first.uppercased() == String(first) else {
            return variant
        }
        let lower = variant.lowercased()
        guard let variantFirst = lower.first else { return variant }
        return variantFirst.uppercased() + String(lower.dropFirst())
    }
}
