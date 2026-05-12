import Foundation

/// Minimal dictionary interface used by language detection.
///
/// Implementations may be in-memory, persistent, system-backed, or composite.
protocol WordDictionary {
    /// Language this dictionary is intended to validate.
    var language: LanguageID { get }
    /// Returns `true` when the provided token is known by this dictionary.
    func contains(_ word: String) -> Bool
    /// Approximate entry count. May be synthetic for dynamic dictionaries.
    var size: Int { get }
}

/// Lightweight normalized dictionary optimized for deterministic tests and fallback corpora.
final class InMemoryDictionary: WordDictionary {
    let language: LanguageID
    private let words: Set<String>

    /// Builds a normalized set from raw words.
    init(language: LanguageID, words: some Sequence<String>) {
        self.language = language
        self.words = Set(words.map { Self.normalize($0) }.filter { !$0.isEmpty })
    }

    /// Checks membership after applying the same normalization pipeline.
    func contains(_ word: String) -> Bool {
        words.contains(Self.normalize(word))
    }

    var size: Int { words.count }

    /// Internal accessor used by n-gram trainers.
    var wordsExposedForNGram: Set<String> { words }

    /// Normalizes token casing/orthography before dictionary comparisons.
    static func normalize(_ word: String) -> String {
        var lower = word.lowercased()
        lower = lower.replacingOccurrences(of: "ё", with: "е")
        return lower.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
