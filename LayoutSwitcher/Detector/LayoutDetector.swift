import Foundation
import os

/// Decision emitted by detector for one committed word token.
enum LayoutDecision: Equatable, Sendable {
    /// Keep the committed token unchanged.
    case keep
    /// Retype the token using corrected text and a target layout language.
    case switchAndRetype(corrected: String, target: LanguageID)
    /// Retype the token and preserve the correction category for feedback.
    case switchAndRetypeWithFeedback(corrected: String, target: LanguageID, kind: CorrectionFeedbackKind)
    /// Avoid switching because the evidence is insufficient or unsafe.
    case ambiguous(reason: String)

    /// Retype payload consumed by pipeline callers.
    var retypePayload: (corrected: String, target: LanguageID, kind: CorrectionFeedbackKind)? {
        switch self {
        case .switchAndRetype(let corrected, let target):
            return (corrected, target, .layoutSwitch)
        case .switchAndRetypeWithFeedback(let corrected, let target, let kind):
            return (corrected, target, kind)
        case .keep, .ambiguous:
            return nil
        }
    }

    static func == (lhs: LayoutDecision, rhs: LayoutDecision) -> Bool {
        switch (lhs, rhs) {
        case (.keep, .keep):
            return true
        case (.ambiguous(let lhsReason), .ambiguous(let rhsReason)):
            return lhsReason == rhsReason
        case let (.switchAndRetype(lhsCorrected, lhsTarget), .switchAndRetype(rhsCorrected, rhsTarget)):
            return lhsCorrected == rhsCorrected && lhsTarget == rhsTarget
        case let (.switchAndRetypeWithFeedback(lhsCorrected, lhsTarget, lhsKind), .switchAndRetypeWithFeedback(rhsCorrected, rhsTarget, rhsKind)):
            return lhsCorrected == rhsCorrected && lhsTarget == rhsTarget && lhsKind == rhsKind
        case let (.switchAndRetype(lhsCorrected, lhsTarget), .switchAndRetypeWithFeedback(rhsCorrected, rhsTarget, _)),
             let (.switchAndRetypeWithFeedback(lhsCorrected, lhsTarget, _), .switchAndRetype(rhsCorrected, rhsTarget)):
            return lhsCorrected == rhsCorrected && lhsTarget == rhsTarget
        default:
            return false
        }
    }
}

/// Language-layout detector combining dictionaries, n-gram scores and optional RO diacritics.
///
/// The detector is pure with respect to system input: it receives a committed
/// token, renders it through each enabled language mapping, scores candidates,
/// and returns a domain decision without posting events or changing layouts.
@MainActor
struct LayoutDetector {
    private static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "Detector")

    /// Tie-break priority when candidates have identical ngram scores.
    /// Lower rank == higher priority. Cyrillic first (ru, uk), then ro, then en.
    static let tieBreakRank: [LanguageID: Int] = [.ru: 0, .uk: 1, .ro: 2, .en: 3]

    /// Keyboard mapping used to render the same physical token in each language.
    let mapping: any KeyboardMapping
    /// Per-language dictionaries used for strong word-existence evidence.
    let dictionaries: [LanguageID: any WordDictionary]
    /// Per-language n-gram models used when dictionary evidence is insufficient.
    let ngrams: [LanguageID: NGramModel]
    /// Scoring strategy, injectable for deterministic detector tests.
    let languageScorer: any LanguageScoring
    /// Static Romanian diacritic resolver used when no dynamic provider is supplied.
    let romanianDiacriticResolver: RomanianDiacriticResolver?
    /// Static Russian yo resolver used when no dynamic provider is supplied.
    let russianYoResolver: RussianYoResolver?
    /// Dynamic resolver provider so user-dictionary changes can affect detection live.
    let romanianDiacriticResolverProvider: (() -> RomanianDiacriticResolver?)?
    /// Dynamic Russian yo resolver provider for future user-corpus updates.
    let russianYoResolverProvider: (() -> RussianYoResolver?)?
    /// Same-language spelling suggestions used by the Cupertino typo corrector.
    let spellingSuggestionProvider: (any SpellingSuggestionProviding)?
    /// User dictionary words intentionally kept in plain Romanian form.
    let romanianPlainOverrideProvider: (() -> Set<String>)?
    /// Threshold profile controlling ambiguity and sensitivity decisions.
    let thresholds: DetectionThresholds

    /// Designated initializer allowing custom dictionary/ngram/resolver wiring.
    init(
        mapping: any KeyboardMapping,
        dictionaries: [LanguageID: any WordDictionary],
        ngrams: [LanguageID: NGramModel],
        languageScorer: (any LanguageScoring)? = nil,
        romanianDiacriticResolver: RomanianDiacriticResolver? = nil,
        russianYoResolver: RussianYoResolver? = nil,
        romanianDiacriticResolverProvider: (() -> RomanianDiacriticResolver?)? = nil,
        russianYoResolverProvider: (() -> RussianYoResolver?)? = nil,
        spellingSuggestionProvider: (any SpellingSuggestionProviding)? = nil,
        romanianPlainOverrideProvider: (() -> Set<String>)? = nil,
        thresholds: DetectionThresholds
    ) {
        self.mapping = mapping
        self.dictionaries = dictionaries
        self.ngrams = ngrams
        self.languageScorer = languageScorer ?? NGramLanguageScorer(ngrams: ngrams)
        self.romanianDiacriticResolver = romanianDiacriticResolver
        self.russianYoResolver = russianYoResolver
        self.romanianDiacriticResolverProvider = romanianDiacriticResolverProvider
        self.russianYoResolverProvider = russianYoResolverProvider
        self.spellingSuggestionProvider = spellingSuggestionProvider
        self.romanianPlainOverrideProvider = romanianPlainOverrideProvider
        self.thresholds = thresholds
    }

    /// Resolves current Romanian diacritic resolver (dynamic provider takes precedence).
    private func currentRomanianDiacriticResolver() -> RomanianDiacriticResolver? {
        romanianDiacriticResolverProvider?() ?? romanianDiacriticResolver
    }

    /// Resolves current Russian yo resolver (dynamic provider takes precedence).
    private func currentRussianYoResolver() -> RussianYoResolver? {
        russianYoResolverProvider?() ?? russianYoResolver
    }

    /// Returns plain Romanian overrides from user dictionary (words intentionally kept without diacritics).
    private func romanianPlainOverrides() -> Set<String> {
        romanianPlainOverrideProvider?() ?? []
    }

    /// Applies dictionary-only correction for very short tokens with exactly one safe non-active hit.
    /// Strict short-word decision. When `bypassActiveLanguageDict` is true the
    /// active-language dictionary guard is skipped. This matters for single-char
    /// tokens: `NSSpellChecker` accepts every isolated Latin letter as a valid
    /// English "word", which would otherwise prevent any single-character
    /// retroactive switch (e.g. `z` → `я`) even when the user has explicitly
    /// opted into single-character correction.
    private func strictShortWordDecision(
        buffer: [WordChar],
        activeLanguage: LanguageID,
        raw: String,
        allowedTargetLanguages: Set<LanguageID>? = nil,
        bypassActiveLanguageDict: Bool = false
    ) -> LayoutDecision? {
        if !bypassActiveLanguageDict, dictionaries[activeLanguage]?.contains(raw) == true {
            return nil
        }

        let allLanguages = Set(dictionaries.keys).union(ngrams.keys)
        let matches = allLanguages.compactMap { language -> (language: LanguageID, text: String)? in
            guard language != activeLanguage else { return nil }
            if let allowedTargetLanguages, !allowedTargetLanguages.contains(language) {
                return nil
            }
            let text = mapping.render(buffer, in: language)
            guard !text.isEmpty,
                  wordMatchesAlphabet(text, of: language),
                  dictionaries[language]?.contains(text) == true else {
                return nil
            }
            return (language, text)
        }

        guard !matches.isEmpty else { return nil }
        let target = matches.min {
            (Self.tieBreakRank[$0.language] ?? .max) < (Self.tieBreakRank[$1.language] ?? .max)
        } ?? matches[0]
        Self.logger.debug("switch lang=\(target.language.rawValue, privacy: .public) text=\"\(target.text, privacy: .public)\" short-word strict-dict matches=\(matches.count, privacy: .public)")
        return .switchAndRetype(corrected: target.text, target: target.language)
    }

    /// Scores one token across supported languages and returns correction decision.
    func decide(
        buffer: [WordChar],
        activeLanguage: LanguageID,
        autoAddRomanianDiacritics: Bool = false,
        autoAddRussianYo: Bool = false,
        correctDoubleCapitals: Bool = false,
        correctDuplicateLetters: Bool = false,
        correctCommonTypos: Bool = false,
        correctSingleCharacterWords: Bool = false,
        allowedTargetLanguages: Set<LanguageID>? = nil,
        thresholds thresholdOverride: DetectionThresholds? = nil
    ) -> LayoutDecision {
        let activeThresholds = thresholdOverride ?? thresholds
        let raw = mapping.render(buffer, in: activeLanguage)
        let length = raw.count
        let ambiguousChars = mapping.ambiguousWordInternalCharacters
        if NonConvertibleTokenGuard.shouldKeep(raw) {
            Self.logger.debug("keep raw=\"\(raw, privacy: .public)\" non-convertible token")
            return .keep
        }
        if length < activeThresholds.minWordLength {
            let strictMin = correctSingleCharacterWords ? 1 : activeThresholds.shortWordStrictMinLength
            if length >= strictMin,
               raw.allSatisfy({ $0.isLetter || ambiguousChars.contains($0) }),
               let decision = strictShortWordDecision(
                   buffer: buffer,
                   activeLanguage: activeLanguage,
                   raw: raw,
                   allowedTargetLanguages: allowedTargetLanguages,
                   bypassActiveLanguageDict: correctSingleCharacterWords && length == 1
               ) {
                return decision
            }
            return .ambiguous(reason: "too short (\(length))")
        }
        if length > activeThresholds.maxWordLength {
            return .ambiguous(reason: "too long (\(length))")
        }
        if !raw.allSatisfy({ $0.isLetter || ambiguousChars.contains($0) }) {
            return .ambiguous(reason: "non-letter content")
        }

        struct Candidate {
            let language: LanguageID
            let text: String
            let dictHit: Bool
            let alphabetMatch: Bool
            let score: LanguageScore
            let isDiacriticVariant: Bool
        }

        var scoreCache: [String: [LanguageID: LanguageScore]] = [:]
        var naturalLanguageProbabilityCache: [String: [LanguageID: Double]] = [:]
        var naturalLanguageProbabilityMisses = Set<String>()
        func score(for text: String, language: LanguageID) -> LanguageScore {
            if let cached = scoreCache[text]?[language] {
                return cached
            }
            let value = languageScorer.score(text, language: language)
            scoreCache[text, default: [:]][language] = value
            return value
        }

        func naturalLanguageProbability(for candidate: Candidate) -> Double? {
            guard candidate.text.count >= activeThresholds.naturalLanguageMinWordLength else {
                return nil
            }
            if let cached = naturalLanguageProbabilityCache[candidate.text]?[candidate.language] {
                return cached
            }
            let missKey = "\(candidate.language.rawValue)\u{0}\(candidate.text)"
            if naturalLanguageProbabilityMisses.contains(missKey) {
                return nil
            }
            guard let probability = languageScorer.naturalLanguageProbability(candidate.text, language: candidate.language) else {
                naturalLanguageProbabilityMisses.insert(missKey)
                return nil
            }
            naturalLanguageProbabilityCache[candidate.text, default: [:]][candidate.language] = probability
            return probability
        }

        func naturalLanguageDecision(_ lhs: Candidate, _ rhs: Candidate) -> Bool? {
            guard lhs.text.count >= activeThresholds.naturalLanguageMinWordLength,
                  rhs.text.count >= activeThresholds.naturalLanguageMinWordLength,
                  let lhsProbability = naturalLanguageProbability(for: lhs),
                  let rhsProbability = naturalLanguageProbability(for: rhs) else {
                return nil
            }
            guard max(lhsProbability, rhsProbability) >= activeThresholds.naturalLanguageMinimumConfidence,
                  abs(lhsProbability - rhsProbability) >= activeThresholds.naturalLanguageTieBreakMargin else {
                return nil
            }
            return lhsProbability > rhsProbability
        }

        func englishRomanianAsciiDecision(_ lhs: Candidate, _ rhs: Candidate) -> Bool? {
            guard lhs.text == rhs.text,
                  Set([lhs.language, rhs.language]) == Set([.en, .ro]),
                  !hasLanguageSpecificCharacters(lhs.text, of: .ro) else {
                return nil
            }
            return lhs.language == .en
        }

        func sameNGramScore(_ lhs: Double, _ rhs: Double) -> Bool {
            abs(lhs - rhs) < 0.000001 ||
            (lhs.isInfinite && rhs.isInfinite && lhs.sign == rhs.sign)
        }

        func isSameCyrillicScriptPair(_ lhs: LanguageID, _ rhs: LanguageID) -> Bool {
            Set([lhs, rhs]).isSubset(of: [.ru, .uk])
        }

        func isNonActionableSameScriptMatch(_ candidate: Candidate) -> Bool {
            isSameCyrillicScriptPair(activeLanguage, candidate.language)
                && InMemoryDictionary.normalize(candidate.text) == InMemoryDictionary.normalize(raw)
        }

        // Stable secondary tie-break when two candidates have identical fallback scores.
        // Cyrillic / Romanian preferred over English; English last; remaining ordering
        // is alphabetic on text for full determinism.
        func bestCandidate(_ list: [Candidate], allowNaturalLanguage: Bool = false) -> Candidate? {
            list.sorted { lhs, rhs in
                if allowNaturalLanguage,
                   let naturalLanguageWinner = naturalLanguageDecision(lhs, rhs) {
                    return naturalLanguageWinner
                }
                if !sameNGramScore(lhs.score.nGramScore, rhs.score.nGramScore) {
                    return lhs.score.nGramScore > rhs.score.nGramScore
                }
                if let asciiWinner = englishRomanianAsciiDecision(lhs, rhs) {
                    return asciiWinner
                }
                let lr = Self.tieBreakRank[lhs.language] ?? Int.max
                let rr = Self.tieBreakRank[rhs.language] ?? Int.max
                if lr != rr { return lr < rr }
                return lhs.text < rhs.text
            }.first
        }

        let allLanguages = Set(dictionaries.keys).union(ngrams.keys).filter { language in
            language == activeLanguage || allowedTargetLanguages?.contains(language) != false
        }
        var candidates: [Candidate] = allLanguages.compactMap { lang in
            let text = mapping.render(buffer, in: lang)
            guard !text.isEmpty else { return nil }
            return Candidate(
                language: lang,
                text: text,
                dictHit: dictionaries[lang]?.contains(text) ?? false,
                alphabetMatch: wordMatchesAlphabet(text, of: lang),
                score: score(for: text, language: lang),
                isDiacriticVariant: false
            )
        }

        let resolver = currentRomanianDiacriticResolver()
        if autoAddRomanianDiacritics {
            if activeLanguage != .ro {
                Self.logger.debug("romanian-diacritic skipped: active language is \(activeLanguage.rawValue, privacy: .public)")
            } else if resolver == nil {
                Self.logger.debug("romanian-diacritic skipped: resolver unavailable")
            } else if let resolver,
                      let romanianBase = candidates.first(where: { $0.language == .ro && !$0.isDiacriticVariant }) {
                let variants = resolver.variants(for: romanianBase.text)
                if variants.isEmpty {
                    Self.logger.debug("romanian-diacritic skipped: no variant for \"\(romanianBase.text, privacy: .public)\"")
                }
                for variant in variants where !candidates.contains(where: { $0.language == .ro && $0.text == variant }) {
                    candidates.append(Candidate(
                        language: .ro,
                        text: variant,
                        dictHit: dictionaries[.ro]?.contains(variant) ?? false,
                        alphabetMatch: wordMatchesAlphabet(variant, of: .ro),
                        score: score(for: variant, language: .ro),
                        isDiacriticVariant: true
                    ))
                }
            }
        } else if activeLanguage == .ro {
            Self.logger.debug("romanian-diacritic skipped: feature disabled")
        }

        for c in candidates {
            Self.logger.debug("candidate lang=\(c.language.rawValue, privacy: .public) text=\"\(c.text, privacy: .public)\" dict=\(c.dictHit, privacy: .public) alphabet=\(c.alphabetMatch, privacy: .public) ngram=\(c.score.nGramScore, privacy: .public)")
        }

        if autoAddRomanianDiacritics, activeLanguage == .ro {
            let diacriticMatches = candidates.filter {
                $0.language == .ro && $0.isDiacriticVariant && $0.dictHit && $0.alphabetMatch && $0.text != raw
            }
            let normalizedRaw = InMemoryDictionary.normalize(raw)
            if romanianPlainOverrides().contains(normalizedRaw) {
                Self.logger.debug("romanian-diacritic skipped: user plain override for \"\(raw, privacy: .public)\"")
            } else if diacriticMatches.count == 1, let target = diacriticMatches.first {
                Self.logger.debug("switch lang=ro text=\"\(target.text, privacy: .public)\" romanian-diacritic=true")
                return .switchAndRetypeWithFeedback(corrected: target.text, target: .ro, kind: .romanianDiacritic)
            }
            let rawDiacriticVariants = candidates.filter { $0.language == .ro && $0.isDiacriticVariant && $0.text != raw }
            if rawDiacriticVariants.count > 1 {
                Self.logger.debug("romanian-diacritic skipped: multiple variants count=\(rawDiacriticVariants.count, privacy: .public)")
            } else if rawDiacriticVariants.contains(where: { !$0.dictHit }) {
                Self.logger.debug("romanian-diacritic skipped: variant is not dictionary hit")
            } else if rawDiacriticVariants.contains(where: { !$0.alphabetMatch }) {
                Self.logger.debug("romanian-diacritic skipped: variant alphabet mismatch")
            }
        }

        if autoAddRussianYo, activeLanguage == .ru {
            if let corrected = currentRussianYoResolver()?.unambiguousCorrection(for: raw),
               raw != corrected,
               wordMatchesAlphabet(corrected, of: .ru) {
                Self.logger.debug("switch lang=ru text=\"\(corrected, privacy: .public)\" russian-yo=true")
                return .switchAndRetypeWithFeedback(corrected: corrected, target: .ru, kind: .russianYo)
            }
        } else if activeLanguage == .ru {
            Self.logger.debug("russian-yo skipped: feature disabled")
        }

        if correctDoubleCapitals,
           let activeDictionary = dictionaries[activeLanguage],
           let corrected = DoubleCapitalCorrector().correction(
               for: raw,
               dictionary: activeDictionary,
               thresholds: activeThresholds
            ) {
            Self.logger.debug("switch lang=\(activeLanguage.rawValue, privacy: .public) text=\"\(corrected, privacy: .public)\" double-capital=true")
            return .switchAndRetypeWithFeedback(corrected: corrected, target: activeLanguage, kind: .doubleCapital)
        }

        if correctDuplicateLetters,
           let active = candidates.first(where: { $0.language == activeLanguage }),
           !active.dictHit,
           let activeDictionary = dictionaries[activeLanguage] {
            let corrector = DuplicateLetterCorrector()
            if let correction = corrector.correction(
                for: raw,
                language: activeLanguage,
                dictionary: activeDictionary,
                scorer: languageScorer,
                thresholds: activeThresholds
            ), wordMatchesAlphabet(correction.corrected, of: activeLanguage) {
                let corrected = chainedDoubleCapitalCorrection(
                    after: correction.corrected,
                    isEnabled: correctDoubleCapitals,
                    dictionary: activeDictionary,
                    thresholds: activeThresholds
                )
                Self.logger.debug("switch lang=\(activeLanguage.rawValue, privacy: .public) text=\"\(corrected, privacy: .public)\" duplicate-letter scoreGain=\(correction.scoreGain, privacy: .public)")
                return .switchAndRetypeWithFeedback(corrected: corrected, target: activeLanguage, kind: .duplicateLetter)
            }
        }

        // 1. Active language is itself valid in dictionary -> usually keep.
        // Some dictionaries are permissive enough to accept wrong-layout noise, so allow
        // a switch only when exactly one non-active dictionary candidate is much stronger.
        if let active = candidates.first(where: { $0.language == activeLanguage }), active.dictHit {
            let competingDictMatches = candidates.filter { $0.dictHit && $0.language != activeLanguage && $0.alphabetMatch }
            if competingDictMatches.count == 1,
               let target = competingDictMatches.first,
               !isSameCyrillicScriptPair(activeLanguage, target.language),
               target.score.nGramScore > active.score.nGramScore + activeThresholds.activeDictionaryOverrideMargin {
                Self.logger.debug("switch lang=\(target.language.rawValue, privacy: .public) text=\"\(target.text, privacy: .public)\" active-dict-overridden targetScore=\(target.score.nGramScore, privacy: .public) activeScore=\(active.score.nGramScore, privacy: .public)")
                return .switchAndRetype(corrected: target.text, target: target.language)
            }
            Self.logger.debug("keep raw=\"\(raw, privacy: .public)\" active dict=true")
            if let correction = typoCorrectedDecision(
                for: raw,
                language: activeLanguage,
                thresholds: activeThresholds
            ) {
                return correction
            }
            return .keep
        }

        if let correction = typoCorrectedDecision(
            for: raw,
            language: activeLanguage,
            thresholds: activeThresholds
        ) {
            return correction
        }

        // 2. Non-active dict matches.
        let dictMatches = candidates.filter { $0.dictHit && $0.language != activeLanguage && $0.alphabetMatch }
        let actionableDictMatches = dictMatches.filter { !isNonActionableSameScriptMatch($0) }
        if !dictMatches.isEmpty, actionableDictMatches.isEmpty {
            Self.logger.debug("keep raw=\"\(raw, privacy: .public)\" same-script dict matches are non-actionable")
            return .keep
        }
        if actionableDictMatches.count == 1, let target = actionableDictMatches.first {
            Self.logger.debug("switch lang=\(target.language.rawValue, privacy: .public) text=\"\(target.text, privacy: .public)\" dict=true unique")
            return .switchAndRetype(corrected: target.text, target: target.language)
        }
        if actionableDictMatches.count > 1 {
            // Multiple dictionaries can accept the same Latin word. In particular,
            // Romanian NSSpellChecker accepts English loanwords such as "hello".
            // Prefer non-English only when the rendered text carries an explicit
            // language signal; otherwise let ngrams decide.
            let nonEnglishSpecific = actionableDictMatches.filter {
                $0.language != .en && hasLanguageSpecificCharacters($0.text, of: $0.language)
            }
            if let target = bestCandidate(nonEnglishSpecific) {
                Self.logger.debug("switch lang=\(target.language.rawValue, privacy: .public) text=\"\(target.text, privacy: .public)\" tie-broken non-EN-specific score=\(target.score.nGramScore, privacy: .public)")
                return .switchAndRetype(corrected: target.text, target: target.language)
            }
            if let best = bestCandidate(actionableDictMatches, allowNaturalLanguage: true) {
                Self.logger.debug("switch lang=\(best.language.rawValue, privacy: .public) text=\"\(best.text, privacy: .public)\" tie-broken score ngram=\(best.score.nGramScore, privacy: .public)")
                return .switchAndRetype(corrected: best.text, target: best.language)
            }
        }

        // 3. Ngram fallback - pick best alphabet-matching candidate, require margin over active.
        let activeCandidate = candidates.first { $0.language == activeLanguage }
        let activeScore = activeCandidate?.score.nGramScore ?? -.infinity
        let alphabetMatched = candidates.filter { $0.alphabetMatch && $0.language != activeLanguage }
        if let best = bestCandidate(alphabetMatched) {
            if best.score.nGramScore > activeScore + activeThresholds.nGramMargin {
                Self.logger.debug("switch lang=\(best.language.rawValue, privacy: .public) score=\(best.score.nGramScore, privacy: .public) > active=\(activeScore, privacy: .public)")
                return .switchAndRetype(corrected: best.text, target: best.language)
            }
        }
        return .keep
    }

    private func typoCorrectedDecision(
        for raw: String,
        language: LanguageID,
        thresholds: DetectionThresholds
    ) -> LayoutDecision? {
        guard correctCommonTypos,
              let activeDictionary = dictionaries[language],
              let spellingSuggestionProvider else {
            return nil
        }
        let corrector = CupertinoCorrector()
        guard let correction = corrector.correction(
            for: raw,
            language: language,
            dictionary: activeDictionary,
            suggestionProvider: spellingSuggestionProvider,
            scorer: languageScorer,
            thresholds: thresholds
        ) else {
            return nil
        }
        Self.logger.debug("switch lang=\(language.rawValue, privacy: .public) text=\"\(correction.corrected, privacy: .public)\" cupertino distance=\(correction.editDistance, privacy: .public) scoreGain=\(correction.scoreGain, privacy: .public)")
        return .switchAndRetypeWithFeedback(corrected: correction.corrected, target: language, kind: .cupertino)
    }

    /// Evaluates the already-rendered token text for corrections that do not require
    /// cross-layout interpretation.
    func decideVisibleTextCorrection(
        text raw: String,
        language activeLanguage: LanguageID,
        autoAddRomanianDiacritics: Bool = false,
        autoAddRussianYo: Bool = false,
        correctDoubleCapitals: Bool = false,
        correctDuplicateLetters: Bool = false,
        correctCommonTypos: Bool = false,
        thresholds thresholdOverride: DetectionThresholds? = nil
    ) -> LayoutDecision {
        let activeThresholds = thresholdOverride ?? thresholds
        let length = raw.count
        if NonConvertibleTokenGuard.shouldKeep(raw) {
            return .keep
        }
        if length < activeThresholds.minWordLength || length > activeThresholds.maxWordLength {
            return .keep
        }
        guard wordMatchesAlphabet(raw, of: activeLanguage) else {
            return .keep
        }

        if autoAddRomanianDiacritics, activeLanguage == .ro {
            let resolver = currentRomanianDiacriticResolver()
            if let resolver {
                let variants = resolver.variants(for: raw)
                let normalizedRaw = InMemoryDictionary.normalize(raw)
                let matches = variants.filter { variant in
                    variant != raw
                        && !romanianPlainOverrides().contains(normalizedRaw)
                        && wordMatchesAlphabet(variant, of: .ro)
                        && dictionaries[.ro]?.contains(variant) == true
                }
                if matches.count == 1, let corrected = matches.first {
                    Self.logger.debug("switch lang=ro text=\"\(corrected, privacy: .public)\" romanian-diacritic=true visible=true")
                    return .switchAndRetypeWithFeedback(corrected: corrected, target: .ro, kind: .romanianDiacritic)
                }
            }
        }

        if autoAddRussianYo, activeLanguage == .ru {
            if let corrected = currentRussianYoResolver()?.unambiguousCorrection(for: raw),
               raw != corrected,
               wordMatchesAlphabet(corrected, of: .ru) {
                Self.logger.debug("switch lang=ru text=\"\(corrected, privacy: .public)\" russian-yo=true visible=true")
                return .switchAndRetypeWithFeedback(corrected: corrected, target: .ru, kind: .russianYo)
            }
        }

        if correctDoubleCapitals,
           let activeDictionary = dictionaries[activeLanguage],
           let corrected = DoubleCapitalCorrector().correction(
               for: raw,
               dictionary: activeDictionary,
               thresholds: activeThresholds
           ) {
            Self.logger.debug("switch lang=\(activeLanguage.rawValue, privacy: .public) text=\"\(corrected, privacy: .public)\" double-capital=true visible=true")
            return .switchAndRetypeWithFeedback(corrected: corrected, target: activeLanguage, kind: .doubleCapital)
        }

        if correctDuplicateLetters,
           let activeDictionary = dictionaries[activeLanguage],
           !activeDictionary.contains(raw) {
            let corrector = DuplicateLetterCorrector()
            if let correction = corrector.correction(
                for: raw,
                language: activeLanguage,
                dictionary: activeDictionary,
                scorer: languageScorer,
                thresholds: activeThresholds
            ), wordMatchesAlphabet(correction.corrected, of: activeLanguage) {
                let corrected = chainedDoubleCapitalCorrection(
                    after: correction.corrected,
                    isEnabled: correctDoubleCapitals,
                    dictionary: activeDictionary,
                    thresholds: activeThresholds
                )
                Self.logger.debug("switch lang=\(activeLanguage.rawValue, privacy: .public) text=\"\(corrected, privacy: .public)\" duplicate-letter visible=true scoreGain=\(correction.scoreGain, privacy: .public)")
                return .switchAndRetypeWithFeedback(corrected: corrected, target: activeLanguage, kind: .duplicateLetter)
            }
        }

        if correctCommonTypos,
           let activeDictionary = dictionaries[activeLanguage],
           let spellingSuggestionProvider {
            let corrector = CupertinoCorrector()
            if let correction = corrector.correction(
                for: raw,
                language: activeLanguage,
                dictionary: activeDictionary,
                suggestionProvider: spellingSuggestionProvider,
                scorer: languageScorer,
                thresholds: activeThresholds
            ) {
                Self.logger.debug("switch lang=\(activeLanguage.rawValue, privacy: .public) text=\"\(correction.corrected, privacy: .public)\" cupertino=true visible=true distance=\(correction.editDistance, privacy: .public) scoreGain=\(correction.scoreGain, privacy: .public)")
                return .switchAndRetypeWithFeedback(corrected: correction.corrected, target: activeLanguage, kind: .cupertino)
            }
        }

        return .keep
    }

    private func chainedDoubleCapitalCorrection(
        after text: String,
        isEnabled: Bool,
        dictionary: any WordDictionary,
        thresholds: DetectionThresholds
    ) -> String {
        guard isEnabled,
              let corrected = DoubleCapitalCorrector().correction(
                  for: text,
                  dictionary: dictionary,
                  thresholds: thresholds
              ) else {
            return text
        }
        return corrected
    }
}
