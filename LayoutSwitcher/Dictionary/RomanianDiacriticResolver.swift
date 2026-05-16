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

/// Main-actor cache for Romanian diacritic resolver indexes.
///
/// Reuses the expensive embedded dictionary index until the user dictionary words change.
@MainActor
final class RomanianDiacriticResolverCache {
    private struct Snapshot {
        let userWords: Set<String>
        let resolver: RomanianDiacriticResolver
        let plainOverrides: Set<String>
    }

    private let embeddedWords: Set<String>
    private let buildResolver: @MainActor (Set<String>) -> RomanianDiacriticResolver
    private var snapshot: Snapshot

    init(
        embeddedWords: Set<String> = Set(EmbeddedDictionaries.romanian().allWords),
        buildResolver: @escaping @MainActor (Set<String>) -> RomanianDiacriticResolver = {
            RomanianDiacriticResolver(words: $0)
        }
    ) {
        self.embeddedWords = embeddedWords
        self.buildResolver = buildResolver
        self.snapshot = Snapshot(
            userWords: [],
            resolver: buildResolver(embeddedWords),
            plainOverrides: []
        )
    }

    /// Returns a cached resolver and rebuilds it only when user words change.
    func resolver(userWords: Set<String>) -> RomanianDiacriticResolver {
        snapshot(for: userWords).resolver
    }

    /// Returns cached plain user words that should suppress diacritic replacement.
    func plainOverrides(userWords: Set<String>) -> Set<String> {
        snapshot(for: userWords).plainOverrides
    }

    private func snapshot(for userWords: Set<String>) -> Snapshot {
        let normalizedUserWords = Self.normalized(userWords)
        guard normalizedUserWords != snapshot.userWords else {
            return snapshot
        }
        let newSnapshot = Snapshot(
            userWords: normalizedUserWords,
            resolver: buildResolver(embeddedWords.union(normalizedUserWords)),
            plainOverrides: Set(normalizedUserWords.filter {
                !RomanianDiacriticResolver.containsRomanianDiacritic($0)
            })
        )
        snapshot = newSnapshot
        return newSnapshot
    }

    private static func normalized(_ words: Set<String>) -> Set<String> {
        Set(words.map { InMemoryDictionary.normalize($0) }.filter { !$0.isEmpty })
    }
}
