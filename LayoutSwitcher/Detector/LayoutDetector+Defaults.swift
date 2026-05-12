import Foundation

/// Default factory wiring for `LayoutDetector`. Composes system spell-check,
/// user dictionaries, embedded fallback corpora, and Romanian diacritic
/// resolver. Pure construction logic — moving it out keeps the algorithmic
/// core of `LayoutDetector` focused on `decide(...)`.
extension LayoutDetector {
    /// Build a default EN/RU/UK/RO detector backed by the system spell-check dictionaries.
    /// Embedded word lists are kept as a final fallback for unit tests / offline use.
    static func defaultMultilingual() -> LayoutDetector {
        let mapping = RuEnQwertyMapping()
        let langs: [LanguageID] = [.en, .ru, .uk, .ro]
        var dicts: [LanguageID: any WordDictionary] = [:]
        for lang in langs {
            dicts[lang] = CompositeDictionary(language: lang, parts: [
                SystemSpellCheckerDictionary(language: lang),
                Self.embeddedFallback(for: lang)
            ])
        }
        let ngrams: [LanguageID: NGramModel] = [
            .en: NGramModels.english(),
            .ru: NGramModels.russian(),
            .uk: NGramModels.ukrainian(),
            .ro: NGramModels.romanian()
        ]
        return LayoutDetector(
            mapping: mapping,
            dictionaries: dicts,
            ngrams: ngrams,
            languageScorer: HybridLanguageScorer(nGramScorer: NGramLanguageScorer(ngrams: ngrams)),
            romanianDiacriticResolver: RomanianDiacriticResolver(words: EmbeddedDictionaries.romanian().allWords)
        )
    }

    /// Multilingual detector with user dictionaries layered above the system spell checker.
    static func defaultMultilingual(
        userEnglish: UserDictionary,
        userRussian: UserDictionary,
        userUkrainian: UserDictionary,
        userRomanian: UserDictionary
    ) -> LayoutDetector {
        let mapping = RuEnQwertyMapping()
        let userDicts: [LanguageID: UserDictionary] = [
            .en: userEnglish,
            .ru: userRussian,
            .uk: userUkrainian,
            .ro: userRomanian
        ]
        var dicts: [LanguageID: any WordDictionary] = [:]
        for (lang, user) in userDicts {
            dicts[lang] = CompositeDictionary(language: lang, parts: [
                user,
                SystemSpellCheckerDictionary(language: lang),
                Self.embeddedFallback(for: lang)
            ])
        }
        let ngrams: [LanguageID: NGramModel] = [
            .en: NGramModels.english(),
            .ru: NGramModels.russian(),
            .uk: NGramModels.ukrainian(),
            .ro: NGramModels.romanian()
        ]
        return LayoutDetector(
            mapping: mapping,
            dictionaries: dicts,
            ngrams: ngrams,
            languageScorer: HybridLanguageScorer(nGramScorer: NGramLanguageScorer(ngrams: ngrams)),
            romanianDiacriticResolverProvider: {
                RomanianDiacriticResolver(words: Array(EmbeddedDictionaries.romanian().allWords) + Array(userRomanian.words))
            },
            romanianPlainOverrideProvider: {
                Set(userRomanian.words.filter { !RomanianDiacriticResolver.containsRomanianDiacritic($0) })
            }
        )
    }

    /// Returns the deepest fallback dictionary for the given language. Tries
    /// the bundled `<lang>.txt` corpus first (full hunspell-derived lists),
    /// then falls back to the in-source `EmbeddedDictionaries` mini-corpus
    /// if the bundle resource is missing (e.g. tests built without resource
    /// staging or stripped builds).
    static func embeddedFallback(for language: LanguageID) -> any WordDictionary {
        BundledDictionaryLoader.loadOrEmbedded(language: language)
    }
}
