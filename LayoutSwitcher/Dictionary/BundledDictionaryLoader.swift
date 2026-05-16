import Foundation
import os

/// Loads plain-text dictionary corpora bundled with the app.
enum BundledDictionaryLoader {
    private static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "Dictionary")
    private static let cachedFallbacks: [LanguageID: InMemoryDictionary] = [
        .en: Self.load(language: .en, resourceName: LanguageID.en.rawValue) ?? EmbeddedDictionaries.english(),
        .ru: Self.load(language: .ru, resourceName: LanguageID.ru.rawValue) ?? EmbeddedDictionaries.russian(),
        .uk: Self.load(language: .uk, resourceName: LanguageID.uk.rawValue) ?? EmbeddedDictionaries.ukrainian(),
        .ro: Self.load(language: .ro, resourceName: LanguageID.ro.rawValue) ?? EmbeddedDictionaries.romanian()
    ]

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

    /// Resolves a dictionary from bundle resources or falls back to built-in embedded corpora.
    static func loadOrEmbedded(language: LanguageID) -> InMemoryDictionary {
        cachedFallbacks[language] ?? EmbeddedDictionaries.english()
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
