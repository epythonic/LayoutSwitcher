/// Chains several dictionaries into one lookup surface.
///
/// The first successful lookup wins semantically, but all parts are queried via `contains`
/// short-circuiting, so ordering is relevant for performance only.
struct CompositeDictionary: WordDictionary {
    let language: LanguageID
    private let parts: [any WordDictionary]

    /// Creates a layered dictionary for a single language.
    init(language: LanguageID, parts: [any WordDictionary]) {
        self.language = language
        self.parts = parts
    }

    /// Returns `true` when any underlying dictionary recognizes the token.
    func contains(_ word: String) -> Bool {
        parts.contains { $0.contains(word) }
    }

    /// Aggregated size estimate of all dictionary parts.
    var size: Int {
        parts.reduce(0) { $0 + $1.size }
    }
}
