import Foundation

/// Resolves unambiguous Russian `е` -> `ё` replacements from known word corpora.
struct RussianYoResolver: Sendable {
    private let variantsByPlain: [String: [String]]
    private let plainWords: Set<String>
    private let preferredPlainCorrections: Set<String>

    /// Conservative plain forms that are safe to auto-convert even when the corpus
    /// also contains a no-yo spelling for compatibility.
    static let defaultPreferredPlainCorrections: Set<String> = [
        "еж", "ежа", "ежам", "ежами", "ежах", "еже", "ежей", "ежи", "ежик", "ежика", "ежике", "ежики", "ежиком",
        "елка", "елкам", "елками", "елках", "елке", "елки", "елкой", "елкою", "елку"
    ]

    /// Builds a resolver index from raw Russian words, preserving the `ё` distinction.
    init(
        words: some Sequence<String>,
        preferredPlainCorrections: Set<String> = []
    ) {
        var variantBuckets: [String: Set<String>] = [:]
        var plainWords: Set<String> = []

        for word in words {
            let normalized = Self.normalizePreservingYo(word)
            guard !normalized.isEmpty else { continue }
            if Self.containsYo(normalized) {
                variantBuckets[Self.plainKey(normalized), default: []].insert(normalized)
            } else {
                plainWords.insert(normalized)
            }
        }

        self.variantsByPlain = variantBuckets.mapValues { Array($0).sorted() }
        self.plainWords = plainWords
        self.preferredPlainCorrections = preferredPlainCorrections
    }

    /// Returns a correction only when exactly one `ё` variant exists and the plain spelling is safe.
    func unambiguousCorrection(for word: String) -> String? {
        let normalized = Self.normalizePreservingYo(word)
        guard normalized.contains("е"),
              !Self.containsYo(normalized) else {
            return nil
        }

        let variants = variantsByPlain[Self.plainKey(normalized)] ?? []
        guard variants.count == 1, let variant = variants.first else {
            return nil
        }
        if plainWords.contains(normalized), !preferredPlainCorrections.contains(normalized) {
            return nil
        }
        return Self.matchCasing(of: word, variant: variant)
    }

    /// Converts `ё` to `е` for plain-key indexing.
    static func plainKey(_ word: String) -> String {
        normalizePreservingYo(word).replacingOccurrences(of: "ё", with: "е")
    }

    /// Checks whether token includes Russian yo.
    static func containsYo(_ word: String) -> Bool {
        word.unicodeScalars.contains { scalar in
            scalar == "ё" || scalar == "Ё"
        }
    }

    private static func normalizePreservingYo(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
