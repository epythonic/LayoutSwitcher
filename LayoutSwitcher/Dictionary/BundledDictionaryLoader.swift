import Foundation
import os

/// Loads plain-text dictionary corpora bundled with the app.
enum BundledDictionaryLoader {
    private static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "Dictionary")

    /// Attempts to read `<resourceName>.txt` and convert lines into an in-memory dictionary.
    static func load(language: LanguageID, resourceName: String, bundle: Bundle = .main) -> InMemoryDictionary? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "txt") else {
            logger.notice("No bundled dictionary file for \(resourceName, privacy: .public).txt")
            return nil
        }
        do {
            let raw = try String(contentsOf: url, encoding: .utf8)
            let words = raw.split(whereSeparator: { $0.isNewline }).map(String.init)
            let dict = InMemoryDictionary(language: language, words: words)
            logger.info("Loaded \(dict.size, privacy: .public) words for \(language.rawValue, privacy: .public)")
            return dict
        } catch {
            logger.error("Failed to load \(resourceName, privacy: .public).txt: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Resolves a dictionary from bundle resources or falls back to built-in embedded corpora.
    static func loadOrEmbedded(language: LanguageID) -> InMemoryDictionary {
        let resourceName = language.rawValue
        if let bundled = load(language: language, resourceName: resourceName) {
            return bundled
        }
        switch language {
        case .en: return EmbeddedDictionaries.english()
        case .ru: return EmbeddedDictionaries.russian()
        case .uk: return EmbeddedDictionaries.ukrainian()
        case .ro: return EmbeddedDictionaries.romanian()
        }
    }
}
