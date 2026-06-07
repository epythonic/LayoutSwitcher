import Foundation
import os

/// Loads plain-text dictionary corpora bundled with the app.
enum BundledDictionaryLoader {
    private static let logger = Logger(subsystem: "GM.LayoutSwitcher", category: "Dictionary")

    /// Attempts to read `<resourceName>.txt` and convert lines into an in-memory dictionary.
    static func load(language: LanguageID, resourceName: String, bundle: Bundle = .main) -> InMemoryDictionary? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "txt") else {
            Self.logger.notice("No bundled dictionary file for \(resourceName, privacy: .public).txt")
            return nil
        }
        do {
            let raw = try String(contentsOf: url, encoding: .utf8)
            let words = raw.split(whereSeparator: { $0.isNewline }).map(String.init)
            let dict = InMemoryDictionary(language: language, words: words)
            Self.logger.info("Loaded \(dict.size, privacy: .public) words for \(language.rawValue, privacy: .public)")
            return dict
        } catch {
            Self.logger.error("Failed to load \(resourceName, privacy: .public).txt: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Resolves a fallback dictionary for `language`, deferred until first use.
    ///
    /// The returned dictionary parses its bundled `<lang>.txt` (multi-MB) only on
    /// the first lookup, so languages outside the active pair are never read and
    /// the parse cost stays off the launch path. The in-source embedded corpus is
    /// the last resort when the bundle resource is missing.
    static func loadOrEmbedded(language: LanguageID) -> any WordDictionary {
        LazyEmbeddedDictionary(language: language) {
            load(language: language, resourceName: language.rawValue) ?? embeddedCorpus(for: language)
        }
    }

    /// In-source corpus used only when the bundled `.txt` resource is unavailable.
    private static func embeddedCorpus(for language: LanguageID) -> InMemoryDictionary {
        switch language {
        case .en: return EmbeddedDictionaries.english()
        case .ru: return EmbeddedDictionaries.russian()
        case .uk: return EmbeddedDictionaries.ukrainian()
        case .ro: return EmbeddedDictionaries.romanian()
        }
    }

    /// Resolves raw corpus words from bundle resources or embedded fallback lists.
    static func rawWordsOrEmbedded(language: LanguageID, bundle: Bundle = .main) -> Set<String> {
        loadRawWords(resourceName: language.rawValue, bundle: bundle)
            ?? Set(EmbeddedDictionaries.rawWords(for: language))
    }

    /// Attempts to read raw `<resourceName>.txt` words without dictionary normalization.
    static func loadRawWords(resourceName: String, bundle: Bundle = .main) -> Set<String>? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "txt") else {
            return nil
        }
        do {
            let raw = try String(contentsOf: url, encoding: .utf8)
            return Set(raw.split(whereSeparator: { $0.isNewline }).map(String.init))
        } catch {
            Self.logger.error("Failed to load raw \(resourceName, privacy: .public).txt: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

/// Builds an embedded fallback dictionary on first lookup, then memoizes it.
///
/// Construction is cheap, so composing a detector for every language parses no
/// word lists until one is actually queried — and languages outside the active
/// pair (which `decide()` never scores) are never parsed at all. Main-actor
/// isolated like the detector that owns it.
@MainActor
final class LazyEmbeddedDictionary: WordDictionary {
    let language: LanguageID
    private let build: @MainActor () -> InMemoryDictionary
    private var loaded: InMemoryDictionary?

    init(language: LanguageID, build: @escaping @MainActor () -> InMemoryDictionary) {
        self.language = language
        self.build = build
    }

    private func resolve() -> InMemoryDictionary {
        if let loaded { return loaded }
        let dictionary = build()
        loaded = dictionary
        return dictionary
    }

    func contains(_ word: String) -> Bool { resolve().contains(word) }

    /// Builds (if needed) and reports the underlying size. Not used on any
    /// production path, so this does not compromise lazy loading at runtime.
    var size: Int { resolve().size }
}
