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
        return checker.guesses(
            forWordRange: range,
            in: word,
            language: SystemSpellCheckerDictionary.isoCode(for: language),
            inSpellDocumentWithTag: 0
        ) ?? []
    }
}
