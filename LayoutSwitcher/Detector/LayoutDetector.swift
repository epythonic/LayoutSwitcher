import Foundation
import os

/// Decision emitted by detector for one committed word token.
enum LayoutDecision: Equatable {
    case keep
    case switchAndRetype(corrected: String, target: LanguageID)
    case ambiguous(reason: String)
}

/// Language-layout detector combining dictionaries, n-gram scores and optional RO diacritics.
@MainActor
final class LayoutDetector {
    private static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "Detector")

    /// Tie-break priority when candidates have identical ngram scores.
    /// Lower rank == higher priority. Cyrillic first (ru, uk), then ro, then en.
    static let tieBreakRank: [LanguageID: Int] = [.ru: 0, .uk: 1, .ro: 2, .en: 3]

    let mapping: any KeyboardMapping
    let dictionaries: [LanguageID: any WordDictionary]
    let ngrams: [LanguageID: NGramModel]
    let languageScorer: any LanguageScoring
    let romanianDiacriticResolver: RomanianDiacriticResolver?
    let romanianDiacriticResolverProvider: (() -> RomanianDiacriticResolver?)?
    let romanianPlainOverrideProvider: (() -> Set<String>)?
    var thresholds: DetectionThresholds

    /// Designated initializer allowing custom dictionary/ngram/resolver wiring.
    init(
        mapping: any KeyboardMapping,
        dictionaries: [LanguageID: any WordDictionary],
        ngrams: [LanguageID: NGramModel],
        languageScorer: (any LanguageScoring)? = nil,
        romanianDiacriticResolver: RomanianDiacriticResolver? = nil,
        romanianDiacriticResolverProvider: (() -> RomanianDiacriticResolver?)? = nil,
        romanianPlainOverrideProvider: (() -> Set<String>)? = nil,
        thresholds: DetectionThresholds = .default
    ) {
        self.mapping = mapping
        self.dictionaries = dictionaries
        self.ngrams = ngrams
        self.languageScorer = languageScorer ?? NGramLanguageScorer(ngrams: ngrams)
        self.romanianDiacriticResolver = romanianDiacriticResolver
        self.romanianDiacriticResolverProvider = romanianDiacriticResolverProvider
        self.romanianPlainOverrideProvider = romanianPlainOverrideProvider
        self.thresholds = thresholds
    }

    /// Resolves current Romanian diacritic resolver (dynamic provider takes precedence).
    private func currentRomanianDiacriticResolver() -> RomanianDiacriticResolver? {
        romanianDiacriticResolverProvider?() ?? romanianDiacriticResolver
    }

    /// Returns plain Romanian overrides from user dictionary (words intentionally kept without diacritics).
    private func romanianPlainOverrides() -> Set<String> {
        romanianPlainOverrideProvider?() ?? []
    }

    /// Applies dictionary-only correction for very short tokens with exactly one safe non-active hit.
    private func strictShortWordDecision(buffer: [WordChar], activeLanguage: LanguageID, raw: String) -> LayoutDecision? {
        if dictionaries[activeLanguage]?.contains(raw) == true {
            return nil
        }

        let allLanguages = Set(dictionaries.keys).union(ngrams.keys)
        let matches = allLanguages.compactMap { language -> (language: LanguageID, text: String)? in
            guard language != activeLanguage else { return nil }
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
        correctSingleCharacterWords: Bool = false
    ) -> LayoutDecision {
        let raw = mapping.render(buffer, in: activeLanguage)
        let length = raw.count
        let ambiguousChars = mapping.ambiguousWordInternalCharacters
        if NonConvertibleTokenGuard.shouldKeep(raw) {
            Self.logger.debug("keep raw=\"\(raw, privacy: .public)\" non-convertible token")
            return .keep
        }
        if length < thresholds.minWordLength {
            let strictMin = correctSingleCharacterWords ? 1 : thresholds.shortWordStrictMinLength
            if length >= strictMin,
               raw.allSatisfy({ $0.isLetter || ambiguousChars.contains($0) }),
               let decision = strictShortWordDecision(buffer: buffer, activeLanguage: activeLanguage, raw: raw) {
                return decision
            }
            return .ambiguous(reason: "too short (\(length))")
        }
        if length > thresholds.maxWordLength {
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
            guard candidate.text.count >= thresholds.naturalLanguageMinWordLength else {
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
            guard lhs.text.count >= thresholds.naturalLanguageMinWordLength,
                  rhs.text.count >= thresholds.naturalLanguageMinWordLength,
                  let lhsProbability = naturalLanguageProbability(for: lhs),
                  let rhsProbability = naturalLanguageProbability(for: rhs) else {
                return nil
            }
            guard max(lhsProbability, rhsProbability) >= thresholds.naturalLanguageMinimumConfidence,
                  abs(lhsProbability - rhsProbability) >= thresholds.naturalLanguageTieBreakMargin else {
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

        let allLanguages = Set(dictionaries.keys).union(ngrams.keys)
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
                return .switchAndRetype(corrected: target.text, target: .ro)
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

        // 1. Active language is itself valid in dictionary -> usually keep.
        // Some dictionaries are permissive enough to accept wrong-layout noise, so allow
        // a switch only when exactly one non-active dictionary candidate is much stronger.
        if let active = candidates.first(where: { $0.language == activeLanguage }), active.dictHit {
            let competingDictMatches = candidates.filter { $0.dictHit && $0.language != activeLanguage && $0.alphabetMatch }
            if competingDictMatches.count == 1,
               let target = competingDictMatches.first,
               target.score.nGramScore > active.score.nGramScore + thresholds.activeDictionaryOverrideMargin {
                Self.logger.debug("switch lang=\(target.language.rawValue, privacy: .public) text=\"\(target.text, privacy: .public)\" active-dict-overridden targetScore=\(target.score.nGramScore, privacy: .public) activeScore=\(active.score.nGramScore, privacy: .public)")
                return .switchAndRetype(corrected: target.text, target: target.language)
            }
            Self.logger.debug("keep raw=\"\(raw, privacy: .public)\" active dict=true")
            return .keep
        }

        // 2. Non-active dict matches.
        let dictMatches = candidates.filter { $0.dictHit && $0.language != activeLanguage && $0.alphabetMatch }
        if dictMatches.count == 1, let target = dictMatches.first {
            Self.logger.debug("switch lang=\(target.language.rawValue, privacy: .public) text=\"\(target.text, privacy: .public)\" dict=true unique")
            return .switchAndRetype(corrected: target.text, target: target.language)
        }
        if dictMatches.count > 1 {
            // Multiple dictionaries can accept the same Latin word. In particular,
            // Romanian NSSpellChecker accepts English loanwords such as "hello".
            // Prefer non-English only when the rendered text carries an explicit
            // language signal; otherwise let ngrams decide.
            let nonEnglishSpecific = dictMatches.filter {
                $0.language != .en && hasLanguageSpecificCharacters($0.text, of: $0.language)
            }
            if let target = bestCandidate(nonEnglishSpecific) {
                Self.logger.debug("switch lang=\(target.language.rawValue, privacy: .public) text=\"\(target.text, privacy: .public)\" tie-broken non-EN-specific score=\(target.score.nGramScore, privacy: .public)")
                return .switchAndRetype(corrected: target.text, target: target.language)
            }
            if let best = bestCandidate(dictMatches, allowNaturalLanguage: true) {
                Self.logger.debug("switch lang=\(best.language.rawValue, privacy: .public) text=\"\(best.text, privacy: .public)\" tie-broken score ngram=\(best.score.nGramScore, privacy: .public)")
                return .switchAndRetype(corrected: best.text, target: best.language)
            }
        }

        // 3. Ngram fallback - pick best alphabet-matching candidate, require margin over active.
        let activeCandidate = candidates.first { $0.language == activeLanguage }
        let activeScore = activeCandidate?.score.nGramScore ?? -.infinity
        let alphabetMatched = candidates.filter { $0.alphabetMatch && $0.language != activeLanguage }
        if let best = bestCandidate(alphabetMatched) {
            if best.score.nGramScore > activeScore + thresholds.nGramMargin {
                Self.logger.debug("switch lang=\(best.language.rawValue, privacy: .public) score=\(best.score.nGramScore, privacy: .public) > active=\(activeScore, privacy: .public)")
                return .switchAndRetype(corrected: best.text, target: best.language)
            }
        }
        return .keep
    }
}
