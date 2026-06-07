import Foundation

/// Supplies same-language spelling suggestions for Cupertino-style typo correction.
@MainActor
protocol SpellingSuggestionProviding {
    /// Returns ordered spelling suggestions for a single token in the requested language.
    func suggestions(for word: String, language: LanguageID) -> [String]
}

/// `NSSpellChecker`-backed suggestion provider.
@MainActor
struct SystemSpellingSuggestionProvider: SpellingSuggestionProviding {
    private let checker: any SpellChecking

    /// Creates provider with explicit spell-check boundary.
    init(checker: any SpellChecking) {
        self.checker = checker
    }

    func suggestions(for word: String, language: LanguageID) -> [String] {
        guard !word.isEmpty else { return [] }
        let range = NSRange(location: 0, length: word.utf16.count)
        let spellLanguage = SystemSpellCheckerDictionary.resolveLanguageCode(
            requested: SystemSpellCheckerDictionary.isoCode(for: language),
            availableLanguages: checker.availableLanguages
        )
        return checker.guesses(
            forWordRange: range,
            in: word,
            language: spellLanguage,
            inSpellDocumentWithTag: 0
        ) ?? []
    }
}

/// Adds small app-curated corrections before falling back to system spell-check guesses.
@MainActor
struct CuratedSpellingSuggestionProvider: SpellingSuggestionProviding {
    private let downstream: any SpellingSuggestionProviding
    private let curated: CuratedCorrections.Table

    /// Creates a provider that prepends curated corrections (loaded from the
    /// bundled resource by default) ahead of downstream guesses.
    init(
        downstream: any SpellingSuggestionProviding,
        curated: CuratedCorrections.Table = CuratedCorrections.loadOrEmbedded()
    ) {
        self.downstream = downstream
        self.curated = curated
    }

    func suggestions(for word: String, language: LanguageID) -> [String] {
        let normalized = InMemoryDictionary.normalize(word)
        let curatedSuggestions = curated[language]?[normalized] ?? []
        let downstreamSuggestions = downstream.suggestions(for: word, language: language)
        return (curatedSuggestions + downstreamSuggestions).reduce(into: [String]()) { result, suggestion in
            let suggestionNormalized = InMemoryDictionary.normalize(suggestion)
            guard !result.contains(where: { InMemoryDictionary.normalize($0) == suggestionNormalized }) else {
                return
            }
            result.append(suggestion)
        }
    }
}

/// Loads curated spelling corrections from a bundled resource, with a minimal
/// embedded fallback so unit tests and stripped builds still apply them.
///
/// Curated entries are a deliberate, documented fallback for words the system
/// spell checker does not itself suggest (e.g. transposition typos the Russian
/// dictionary misses). They are applied ahead of system guesses. Prefer fixing
/// the general corrector over growing this list — see docs/FullAudit.
enum CuratedCorrections {
    /// Language → normalized misspelling → ordered replacement suggestions.
    typealias Table = [LanguageID: [String: [String]]]

    /// Resource-backed table, falling back to the embedded minimal set.
    static func loadOrEmbedded(bundle: Bundle = .main) -> Table {
        parse(resourceContents(bundle: bundle)) ?? embedded
    }

    /// Minimal embedded fallback used when the bundled resource is unavailable.
    static let embedded: Table = [
        .ru: [
            "заклучил": ["заключил"],
            "закулчил": ["заключил"]
        ]
    ]

    private static func resourceContents(bundle: Bundle) -> String? {
        guard let url = bundle.url(forResource: "curated-corrections", withExtension: "txt") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Parses `<lang> <wrong> <correct> [<correct2> ...]` lines; `#` lines and
    /// blanks are ignored. Misspelling keys are normalized to match lookups.
    static func parse(_ raw: String?) -> Table? {
        guard let raw else { return nil }
        var table: Table = [:]
        for line in raw.split(whereSeparator: { $0.isNewline }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let fields = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard fields.count >= 3, let language = LanguageID(rawValue: fields[0]) else { continue }
            let key = InMemoryDictionary.normalize(fields[1])
            table[language, default: [:]][key, default: []].append(contentsOf: fields[2...])
        }
        return table.isEmpty ? nil : table
    }
}

/// Memoizes downstream suggestions in a bounded FIFO cache.
///
/// The Cupertino typo path queries `NSSpellChecker.guesses` synchronously on the
/// keystroke-handling main thread for every eligible token. Unlike membership
/// checks (`SystemSpellCheckerDictionary`), guesses were uncached, so repeated
/// tokens paid the system IPC cost every time. This decorator caches the result
/// per `(language, word)` to keep the hot path responsive.
@MainActor
final class CachedSpellingSuggestionProvider: SpellingSuggestionProviding {
    private struct Key: Hashable {
        let language: LanguageID
        let word: String
    }

    private let downstream: any SpellingSuggestionProviding
    private let capacity: Int
    private var cache: [Key: [String]] = [:]
    private var insertionOrder: [Key] = []

    /// Creates a caching provider with a bounded entry count.
    init(downstream: any SpellingSuggestionProviding, capacity: Int = 4_000) {
        self.downstream = downstream
        self.capacity = max(1, capacity)
    }

    func suggestions(for word: String, language: LanguageID) -> [String] {
        let key = Key(language: language, word: word)
        if let cached = cache[key] { return cached }
        let result = downstream.suggestions(for: word, language: language)
        cache[key] = result
        insertionOrder.append(key)
        if insertionOrder.count > capacity {
            let evictCount = insertionOrder.count - capacity
            for evicted in insertionOrder.prefix(evictCount) {
                cache.removeValue(forKey: evicted)
            }
            insertionOrder.removeFirst(evictCount)
        }
        return result
    }
}
