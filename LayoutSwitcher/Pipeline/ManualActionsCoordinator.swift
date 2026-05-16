import Foundation
import os

/// Encapsulates user-triggered hot-key actions over the committed-word history:
/// "force retype last word" and "convert last sentence". Keeps these flows out of
/// `TypingPipeline` so the latter stays focused on auto-detection and event routing.
@MainActor
final class ManualActionsCoordinator {
    private static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "ManualActions")

    private let detector: LayoutDetector
    private let retyper: Retyper
    private let inputSources: any InputSourceManaging
    private let recents: RecentSwitches
    private let stats: UsageStats
    private let focused: FocusedAppObserver
    private let retypeDispatcher: RetypeDispatcher
    private let tunables: PipelineTunables
    private let committedHistoryProvider: () -> [CommittedWord]
    private let now: @MainActor () -> Date
    weak var appState: AppState?
    private var currentDetectionThresholds: DetectionThresholds {
        appState?.detectionSensitivity.thresholds ?? detector.thresholds
    }

    /// Wires all collaborators. `committedHistoryProvider` is a closure so the
    /// coordinator can read the most recent history without owning it.
    init(
        detector: LayoutDetector,
        retyper: Retyper,
        inputSources: any InputSourceManaging,
        recents: RecentSwitches,
        stats: UsageStats,
        focused: FocusedAppObserver,
        retypeDispatcher: RetypeDispatcher,
        tunables: PipelineTunables,
        committedHistoryProvider: @escaping () -> [CommittedWord],
        now: @escaping @MainActor () -> Date
    ) {
        self.detector = detector
        self.retyper = retyper
        self.inputSources = inputSources
        self.recents = recents
        self.stats = stats
        self.focused = focused
        self.retypeDispatcher = retypeDispatcher
        self.tunables = tunables
        self.committedHistoryProvider = committedHistoryProvider
        self.now = now
    }

    /// Manual override for the most-recent word that escaped auto-switch — re-runs
    /// detection and retypes if the verdict is `.switchAndRetype`.
    func forceRetypeLastWord() {
        guard let word = committedHistoryProvider().last else {
            appState?.lastActionDescription = String(localized: "pipeline.result.no-recent-word")
            return
        }
        guard let activeLanguage = LanguageID(inputSourceLanguageCode: inputSources.current?.primaryLanguage) else {
            appState?.lastActionDescription = String(localized: "pipeline.result.no-active-layout")
            return
        }
        if wasAutoSwitched(word) {
            appState?.lastActionDescription = String(localized: "pipeline.result.already-auto-switched")
            return
        }
        let decision = detector.decide(
            buffer: word.characters,
            activeLanguage: activeLanguage,
            autoAddRomanianDiacritics: appState?.autoAddRomanianDiacritics == true,
            autoAddRussianYo: appState?.autoAddRussianYo == true,
            correctDoubleCapitals: appState?.correctDoubleCapitals == true,
            correctDuplicateLetters: appState?.correctDuplicateLetters == true,
            correctCommonTypos: appState?.correctCommonTypos == true,
            correctSingleCharacterWords: appState?.correctSingleCharacterWords == true,
            allowedTargetLanguages: allowedCrossLayoutTargets(from: activeLanguage),
            thresholds: currentDetectionThresholds
        )
        switch decision {
        case .keep:
            appState?.lastActionDescription = String(localized: "pipeline.result.word-correct")
        case .ambiguous(let reason):
            appState?.lastActionDescription = String(
                format: String(localized: "pipeline.result.ambiguous"),
                reason
            )
        case .switchAndRetype(_, _), .switchAndRetypeWithFeedback(_, _, _):
            guard let payload = decision.retypePayload else { return }
            let corrected = payload.corrected
            let target = payload.target
            guard !retypeDispatcher.isRetyping else { return }
            Self.logger.info("force-retype: \"\(word.text, privacy: .public)\" → \"\(corrected, privacy: .public)\" target=\(target.rawValue, privacy: .public)")
            retypeDispatcher.setRetypingFlag(true)
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.retypeDispatcher.setRetypingFlag(false) }
                let result = await self.retyper.retypeResult(
                    original: word.characters,
                    corrected: corrected,
                    targetLanguage: target,
                    separator: word.separator,
                    separatorKeyCode: word.separatorKeyCode,
                    separatorFlags: word.separatorFlags
                )
                if result.succeeded {
                    self.appState?.lastActionDescription = String(
                        format: String(localized: "pipeline.result.retyped"),
                        word.text,
                        corrected
                    )
                    self.stats.recordManualSwitch()
                } else {
                    self.appState?.lastActionDescription = String(localized: "pipeline.result.retype-failed")
                }
            }
        }
    }

    /// Manual sentence-scope retype: walks back from the latest committed word until a
    /// sentence boundary, re-runs detection for each word (aggressive mode — includes
    /// 1-char tokens), and retypes the trailing contiguous run of switches that share
    /// one target language.
    func forceConvertLastSentence() {
        guard let activeLanguage = LanguageID(inputSourceLanguageCode: inputSources.current?.primaryLanguage) else {
            appState?.lastActionDescription = String(localized: "pipeline.result.no-active-layout")
            return
        }
        let sentence = collectLastSentenceWords()
        guard !sentence.isEmpty else {
            appState?.lastActionDescription = String(localized: "pipeline.result.no-recent-sentence")
            return
        }

        var run: [PendingRetypeCandidate] = []
        var runTarget: LanguageID?
        for word in sentence {
            if wasAutoSwitched(word) {
                run.removeAll()
                runTarget = nil
                continue
            }
            let decision = detector.decide(
                buffer: word.characters,
                activeLanguage: activeLanguage,
                autoAddRomanianDiacritics: appState?.autoAddRomanianDiacritics == true,
                autoAddRussianYo: appState?.autoAddRussianYo == true,
                correctDoubleCapitals: appState?.correctDoubleCapitals == true,
                correctDuplicateLetters: appState?.correctDuplicateLetters == true,
                correctCommonTypos: appState?.correctCommonTypos == true,
                correctSingleCharacterWords: true,
                allowedTargetLanguages: allowedCrossLayoutTargets(from: activeLanguage),
                thresholds: currentDetectionThresholds
            )
            switch decision {
            case .switchAndRetype(_, _), .switchAndRetypeWithFeedback(_, _, _):
                guard let payload = decision.retypePayload else { continue }
                let corrected = payload.corrected
                let target = payload.target
                if let current = runTarget, current != target {
                    run.removeAll()
                }
                runTarget = target
                let originalText = detector.mapping.render(word.characters, in: activeLanguage)
                run.append(PendingRetypeCandidate(
                    word: word,
                    activeLanguage: activeLanguage,
                    targetLanguage: target,
                    corrected: corrected,
                    originalText: originalText,
                    correctionKind: payload.kind
                ))
            case .keep, .ambiguous:
                run.removeAll()
                runTarget = nil
            }
        }

        guard !run.isEmpty else {
            appState?.lastActionDescription = String(localized: "pipeline.result.no-recent-sentence")
            return
        }
        Self.logger.info("force-sentence: \(run.count, privacy: .public) word(s) target=\(run[0].targetLanguage.rawValue, privacy: .public)")
        retypeDispatcher.resetCooldown()
        retypeDispatcher.dispatch(run)
    }

    /// True if a `RecentSwitchEntry` already represents this word's auto-switch
    /// (within the configured match window).
    private func wasAutoSwitched(_ word: CommittedWord) -> Bool {
        recents.entries.contains { entry in
            abs(entry.timestamp.timeIntervalSince(word.committedAt)) < tunables.wasAutoSwitchedMatchWindow
        }
    }

    private func allowedCrossLayoutTargets(from sourceLanguage: LanguageID) -> Set<LanguageID>? {
        guard let configuredTargets = appState?.enabledCrossLayoutTargets(from: sourceLanguage) else {
            return nil
        }
        return configuredTargets.intersection(inputSources.enabledLayoutLanguages())
    }

    /// Walks `committedHistory` backwards collecting words that belong to the
    /// current sentence — stops at sentence-ending punctuation, app change,
    /// expiration, or word cap.
    private func collectLastSentenceWords() -> [CommittedWord] {
        let currentTime = now()
        let currentBundleID = focused.bundleID
        var collected: [CommittedWord] = []
        for (index, word) in committedHistoryProvider().reversed().enumerated() {
            if currentTime.timeIntervalSince(word.committedAt) > tunables.sentenceConvertMaxAge { break }
            if word.bundleID != currentBundleID { break }
            if index > 0, case .punctuation(let c) = word.separator, tunables.sentenceEndingPunctuation.contains(c) {
                break
            }
            if index > 0, case .enter = word.separator { break }
            if index > 0, case .tab = word.separator { break }
            collected.append(word)
            if collected.count >= tunables.sentenceConvertMaxWords { break }
        }
        return collected.reversed()
    }
}
