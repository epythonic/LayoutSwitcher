import AppKit
import Foundation
import os

/// Minimal interface that `SystemSpellCheckerDictionary` consumes from `NSSpellChecker`.
/// Exposed for testability (mock the spell checker without hitting macOS APIs).
@MainActor
protocol SpellChecking {
    func checkSpelling(
        of stringToCheck: String,
        startingAt startingOffset: Int,
        language: String?,
        wrap wrapFlag: Bool,
        inSpellDocumentWithTag tag: Int,
        wordCount: UnsafeMutablePointer<Int>?
    ) -> NSRange
    func guesses(
        forWordRange range: NSRange,
        in string: String,
        language: String?,
        inSpellDocumentWithTag tag: Int
    ) -> [String]?
    var availableLanguages: [String] { get }
}

extension NSSpellChecker: SpellChecking {}

/// Backs `WordDictionary` with `NSSpellChecker` — exposes the full system spell-check
/// dictionary for the requested language (the same database used by Mail, Pages, Notes…).
@MainActor
final class SystemSpellCheckerDictionary: WordDictionary {
    private static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "SystemSpell")
    /// Default bounded cache capacity for spell-check lookup memoization.
    nonisolated static let defaultCacheCapacity = 10_000

    let language: LanguageID
    let isoLanguage: String
    private let checker: any SpellChecking
    private let cacheCapacity: Int
    private var cache: [String: Bool] = [:]
    private var cacheOrder: [String] = []

    /// Creates system-backed dictionary adapter with optional checker/cache overrides.
    init(
        language: LanguageID,
        checker: any SpellChecking,
        cacheCapacity: Int = SystemSpellCheckerDictionary.defaultCacheCapacity
    ) {
        self.language = language
        self.isoLanguage = Self.isoCode(for: language)
        self.checker = checker
        self.cacheCapacity = cacheCapacity
        if !checker.availableLanguages.contains(isoLanguage) {
            Self.logger.notice("System spell checker has no dictionary for \(self.isoLanguage, privacy: .public); falling back to lookups will always return false")
        }
    }

    /// Test-only view into the cache size for verifying eviction.
    var cachedEntryCount: Int { cache.count }

    /// Returns dictionary membership using cached spell-check lookup.
    func contains(_ word: String) -> Bool {
        let normalized = word.lowercased()
        if let cached = cache[normalized] { return cached }
        let result = lookup(normalized)
        insertIntoCache(normalized, result: result)
        return result
    }

    var size: Int { Int.max }

    /// Inserts lookup result into bounded FIFO cache.
    private func insertIntoCache(_ word: String, result: Bool) {
        cache[word] = result
        cacheOrder.append(word)
        if cacheOrder.count > cacheCapacity {
            // FIFO trim — simpler than LRU and sufficient to bound memory.
            let evictCount = cacheOrder.count - cacheCapacity
            for evicted in cacheOrder.prefix(evictCount) {
                cache.removeValue(forKey: evicted)
            }
            cacheOrder.removeFirst(evictCount)
        }
    }

    /// Returns `true` if the spell checker knows the word in this language.
    private func lookup(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        var wordCount: Int = 0
        let range = checker.checkSpelling(
            of: word,
            startingAt: 0,
            language: isoLanguage,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: &wordCount
        )
        // checkSpelling returns the range of the first MISSPELLED segment.
        // The word is recognised when no misspelling is found.
        return range.location == NSNotFound || range.length == 0
    }

    /// Maps internal language identifier to `NSSpellChecker` language code.
    static func isoCode(for language: LanguageID) -> String {
        switch language {
        case .en: return "en"
        case .ru: return "ru"
        case .ro: return "ro"
        case .uk: return "uk"
        }
    }
}
