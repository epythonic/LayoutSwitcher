import CoreGraphics
import Foundation
import os

/// Coordinates key events, word buffering, layout detection, and retype dispatch.
///
/// The pipeline is the main runtime boundary between low-level keyboard input
/// and high-level app services such as statistics, exclusions, learning cache,
/// notifications, and feedback.
@MainActor
final class TypingPipeline {
    private static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "Pipeline")
    let tunables: PipelineTunables

    private let buffer: WordBuffer
    private let focused: FocusedAppObserver
    private let detector: LayoutDetector
    private let retyper: Retyper
    private let inputSources: any InputSourceManaging
    private let now: @MainActor () -> Date
    let exclusions: ExclusionList
    let stats: UsageStats
    let recents: RecentSwitches
    let perAppLayouts: PerAppLayoutPreferences?
    private let learningCache: LearningCache?
    private let presentationDetector: PresentationModeDetector?
    private let notificationManager: NotificationManager?
    private let retypeDispatcher: RetypeDispatcher
    private let manualActions: ManualActionsCoordinator
    weak var appState: AppState? {
        didSet {
            retypeDispatcher.appState = appState
            manualActions.appState = appState
        }
    }
    var hotkeyCoordinator: HotkeyCoordinator? {
        didSet { retypeDispatcher.hotkeyCoordinator = hotkeyCoordinator }
    }
    var focusContextDidChange: (() -> Void)?
    var isRetyping: Bool { retypeDispatcher.isRetyping }
    private var suppressUntilSeparator = false
    private let sequenceDetector: SequenceDetector
    private(set) var committedHistory: [CommittedWord] = []
    private var currentDetectionThresholds: DetectionThresholds {
        appState?.detectionSensitivity.thresholds ?? detector.thresholds
    }

    init(
        buffer: WordBuffer,
        focused: FocusedAppObserver,
        detector: LayoutDetector,
        retyper: Retyper,
        inputSources: any InputSourceManaging,
        learningCache: LearningCache? = nil,
        soundFeedback: SoundFeedbackPlayer? = nil,
        visualFeedback: VisualFeedbackPlayer? = nil,
        presentationDetector: PresentationModeDetector? = nil,
        notificationManager: NotificationManager? = nil,
        exclusions: ExclusionList,
        stats: UsageStats,
        recents: RecentSwitches,
        perAppLayouts: PerAppLayoutPreferences? = nil,
        tunables: PipelineTunables,
        bundleNameProvider: @escaping @MainActor (String) -> String? = { _ in nil },
        sleepBeforeSequenceFlush: @escaping @MainActor @Sendable (Duration) async -> Void,
        now: @escaping @MainActor () -> Date
    ) {
        self.buffer = buffer
        self.focused = focused
        self.detector = detector
        self.retyper = retyper
        self.inputSources = inputSources
        self.now = now
        self.learningCache = learningCache
        self.presentationDetector = presentationDetector
        self.notificationManager = notificationManager
        self.exclusions = exclusions
        self.stats = stats
        self.recents = recents
        self.perAppLayouts = perAppLayouts
        self.tunables = tunables
        let dispatcher = RetypeDispatcher(
            retyper: retyper,
            stats: stats,
            recents: recents,
            notificationManager: notificationManager,
            soundFeedback: soundFeedback,
            visualFeedback: visualFeedback,
            tunables: tunables,
            bundleNameProvider: bundleNameProvider,
            now: now
        )
        self.retypeDispatcher = dispatcher
        // committedHistoryProvider deferred to first read after `self` is fully built.
        var historyProvider: () -> [CommittedWord] = { [] }
        self.manualActions = ManualActionsCoordinator(
            detector: detector,
            retyper: retyper,
            inputSources: inputSources,
            recents: recents,
            stats: stats,
            focused: focused,
            retypeDispatcher: dispatcher,
            tunables: tunables,
            committedHistoryProvider: { historyProvider() },
            now: now
        )
        self.sequenceDetector = SequenceDetector(sleepBeforeFlush: sleepBeforeSequenceFlush)

        // Now that `self` is fully constructed, route the placeholder closure to
        // read live `committedHistory` from this instance.
        historyProvider = { [weak self] in self?.committedHistory ?? [] }

        sequenceDetector.isBufferIdle = { [weak buffer] in
            buffer?.characters.isEmpty ?? true
        }
        sequenceDetector.onFlushReady = { [weak self] candidates in
            self?.retypeDispatcher.dispatch(candidates)
        }

        buffer.bundleIDProvider = { [weak focused] in focused?.bundleID }

        buffer.onAppended = { char in
            Self.logger.debug("appended u=\(char.unicode, privacy: .public)")
        }
        buffer.onCommitted = { [weak self] word in
            Self.logger.info("committed \"\(word.text, privacy: .public)\" sep=\(String(describing: word.separator), privacy: .public) app=\(word.bundleID ?? "?", privacy: .public)")
            guard let self else { return }
            self.committedHistory.append(word)
            let cap = self.tunables.maxCommittedHistory
            if self.committedHistory.count > cap {
                self.committedHistory.removeFirst(self.committedHistory.count - cap)
            }
            self.stats.recordWordCommitted()
            self.evaluate(word)
        }
        buffer.onReset = { reason in
            Self.logger.debug("reset reason=\(String(describing: reason), privacy: .public)")
        }

        focused.onChange = { [weak self, weak buffer] in
            self?.suppressUntilSeparator = false
            self?.resetPendingSequence(clearCooldown: true)
            buffer?.reset(reason: .appChanged)
            self?.applyPreferredLayoutForFocusedApp()
            self?.notifyFocusContextDidChange()
        }
    }

    /// Selects the configured preferred input source for the newly-focused app, if any.
    /// Skipped when master toggle is off, snoozed, or the layout is already current.
    private func applyPreferredLayoutForFocusedApp() {
        guard let perAppLayouts else { return }
        guard appState?.isEnabled != false else { return }
        guard appState?.isSnoozed != true else { return }
        guard let bundleID = focused.bundleID,
              let preferred = perAppLayouts.preferredLayout(for: bundleID) else {
            return
        }
        if inputSources.current?.id == preferred { return }
        guard let layout = inputSources.keyboardLayouts().first(where: { $0.id == preferred }) else {
            Self.logger.notice("per-app layout: preferred source \"\(preferred, privacy: .public)\" not installed for \(bundleID, privacy: .public)")
            return
        }
        let status = inputSources.select(layout)
        if status == noErr {
            inputSources.refresh()
            Self.logger.info("per-app layout: switched to \(preferred, privacy: .public) for \(bundleID, privacy: .public)")
        } else {
            Self.logger.error("per-app layout: TISSelectInputSource failed status=\(status, privacy: .public)")
        }
    }

    private func notifyFocusContextDidChange() {
        focusContextDidChange?()
    }

    private func evaluate(_ word: CommittedWord) {
        guard !isRetyping else { return }
        if appState?.isEnabled == false {
            resetPendingSequence(clearCooldown: true)
            return
        }
        guard let activeLanguage = LanguageID(inputSourceLanguageCode: inputSources.current?.primaryLanguage) else {
            resetPendingSequence(clearCooldown: true)
            return
        }
        if appState?.isSnoozed == true {
            resetPendingSequence()
            Self.logger.info("decision: auto-switch suppressed (snoozed)")
            return
        }
        if presentationDetector?.isPresenting == true {
            resetPendingSequence()
            Self.logger.info("decision: auto-switch suppressed (presentation mode)")
            return
        }

        // Auto-switch only on safe separators. Enter would submit a chat message before
        // we could undo; Tab might shift focus out of the input.
        switch word.separator {
        case .enter, .tab:
            Self.logger.debug("auto-switch suppressed for separator=\(String(describing: word.separator), privacy: .public)")
            resetPendingSequence(clearCooldown: true)
            return
        case .space, .punctuation:
            break
        }
        guard isSafeFinalSeparator(word.separator) else {
            resetPendingSequence(clearCooldown: true)
            return
        }

        if let visibleLanguage = visibleCorrectionLanguage(for: word.text, fallback: activeLanguage) {
            if let layoutDecision = preferredCrossLayoutDecisionBeforeVisibleCorrection(
                word: word,
                activeLanguage: activeLanguage,
                visibleLanguage: visibleLanguage
            ) {
                if layoutDecision == .keep {
                    resetPendingSequence(clearCooldown: true)
                } else {
                    let sourceLanguage = preferredDecisionSourceLanguage(
                        layoutDecision,
                        visibleLanguage: visibleLanguage,
                        fallback: activeLanguage
                    )
                    _ = applyRetypeDecision(layoutDecision, word: word, activeLanguage: sourceLanguage, originalText: word.text)
                }
                return
            }
            if applyVisibleTextCorrection(text: word.text, language: visibleLanguage, word: word) {
                return
            }
        }
        for renderedLanguage in sameLanguageCorrectionCandidates(activeLanguage: activeLanguage) {
            guard renderedLanguage == .ru else { continue }
            let renderedText = detector.mapping.render(word.characters, in: renderedLanguage)
            guard renderedText != word.text,
                  visibleCorrectionLanguage(for: renderedText, fallback: renderedLanguage) == renderedLanguage else {
                continue
            }
            if applyRenderedRussianYoCorrection(text: renderedText, word: word) {
                return
            }
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
            resetPendingSequence(clearCooldown: true)
            return
        case .ambiguous(let reason):
            resetPendingSequence(clearCooldown: true)
            Self.logger.debug("ambiguous: \(reason, privacy: .public)")
        case .switchAndRetype(_, _), .switchAndRetypeWithFeedback(_, _, _):
            _ = applyRetypeDecision(decision, word: word, activeLanguage: activeLanguage)
        }
    }

    private func sameLanguageCorrectionCandidates(activeLanguage: LanguageID) -> [LanguageID] {
        [activeLanguage] + LanguageID.allCases.filter { $0 != activeLanguage }
    }

    private func allowedCrossLayoutTargets(from sourceLanguage: LanguageID) -> Set<LanguageID>? {
        guard let configuredTargets = appState?.enabledCrossLayoutTargets(from: sourceLanguage) else {
            return nil
        }
        return configuredTargets.intersection(inputSources.enabledLayoutLanguages())
    }

    private func visibleCorrectionLanguage(for text: String, fallback: LanguageID) -> LanguageID? {
        guard !text.isEmpty, text.allSatisfy(\.isLetter) else { return nil }
        if detector.wordMatchesAlphabet(text, of: fallback) {
            return fallback
        }
        let matches = LanguageID.allCases.filter { detector.wordMatchesAlphabet(text, of: $0) }
        if matches.contains(.ru) { return .ru }
        if matches.contains(.ro),
           let romanianPayload = visibleTextCorrectionDecision(text: text, language: .ro).retypePayload,
           romanianPayload.target == .ro,
           romanianPayload.kind != .layoutSwitch {
            return .ro
        }
        if matches.contains(.ro),
           detector.dictionaries[.ro]?.contains(text) == true,
           detector.dictionaries[.en]?.contains(text) != true {
            return .ro
        }
        if matches.contains(.en) { return .en }
        if matches.contains(.ro) { return .ro }
        if matches.contains(.uk) { return .uk }
        return nil
    }

    private func preferredCrossLayoutDecisionBeforeVisibleCorrection(
        word: CommittedWord,
        activeLanguage: LanguageID,
        visibleLanguage: LanguageID
    ) -> LayoutDecision? {
        let rawLayoutDecision = detector.decide(
            buffer: word.characters,
            activeLanguage: activeLanguage,
            correctSingleCharacterWords: appState?.correctSingleCharacterWords == true,
            allowedTargetLanguages: allowedCrossLayoutTargets(from: activeLanguage),
            thresholds: currentDetectionThresholds
        )
        let layoutSwitchDecision: LayoutDecision?
        if let payload = rawLayoutDecision.retypePayload,
           payload.kind == .layoutSwitch,
           payload.target != activeLanguage,
           isRetypeTargetAllowed(payload.target, from: activeLanguage) {
            layoutSwitchDecision = rawLayoutDecision
        } else {
            layoutSwitchDecision = nil
        }
        var activeRenderedDictionaryDecision: LayoutDecision?
        let visibleDecision = visibleTextCorrectionDecision(text: word.text, language: visibleLanguage)
        if shouldVisibleLatinOutrankRenderedCorrection(word.text, activeLanguage: activeLanguage, visibleLanguage: visibleLanguage) {
            if let visiblePayload = visibleDecision.retypePayload,
               visiblePayload.target == visibleLanguage,
               visiblePayload.kind != .layoutSwitch {
                return visibleDecision
            }
            if isKnownVisibleLatinWord(word.text, visibleLanguage: visibleLanguage) {
                return .keep
            }
        }
        for renderedLanguage in sameLanguageCorrectionCandidates(activeLanguage: activeLanguage) where renderedLanguage != visibleLanguage {
            guard isRetypeTargetAllowed(renderedLanguage, from: activeLanguage) else {
                continue
            }
            let renderedText = detector.mapping.render(word.characters, in: renderedLanguage)
            guard renderedText != word.text,
                  visibleCorrectionLanguage(for: renderedText, fallback: renderedLanguage) == renderedLanguage else {
                continue
            }
            let renderedDecision = visibleTextCorrectionDecision(text: renderedText, language: renderedLanguage)
            guard let renderedPayload = renderedDecision.retypePayload,
                  renderedPayload.target == renderedLanguage else {
                continue
            }
            return renderedDecision
        }
        for renderedLanguage in sameLanguageCorrectionCandidates(activeLanguage: activeLanguage) where renderedLanguage != visibleLanguage {
            guard isRetypeTargetAllowed(renderedLanguage, from: activeLanguage) else {
                continue
            }
            let renderedText = detector.mapping.render(word.characters, in: renderedLanguage)
            guard renderedLanguage == activeLanguage,
                  renderedText != word.text,
                  detector.wordMatchesAlphabet(renderedText, of: renderedLanguage),
                  detector.dictionaries[renderedLanguage]?.contains(renderedText) == true else {
                continue
            }
            activeRenderedDictionaryDecision = .switchAndRetype(corrected: renderedText, target: renderedLanguage)
            break
        }
        if visibleLanguage != activeLanguage {
            return activeRenderedDictionaryDecision
        }
        return activeRenderedDictionaryDecision ?? layoutSwitchDecision
    }

    private func isRetypeTargetAllowed(_ target: LanguageID, from activeLanguage: LanguageID) -> Bool {
        if target == activeLanguage { return true }
        guard let allowedTargets = allowedCrossLayoutTargets(from: activeLanguage) else {
            return true
        }
        return allowedTargets.contains(target)
    }

    private func preferredDecisionSourceLanguage(
        _ decision: LayoutDecision,
        visibleLanguage: LanguageID,
        fallback: LanguageID
    ) -> LanguageID {
        guard let payload = decision.retypePayload,
              payload.target == visibleLanguage,
              payload.kind != .layoutSwitch else {
            return fallback
        }
        return visibleLanguage
    }

    private func shouldVisibleLatinOutrankRenderedCorrection(
        _ text: String,
        activeLanguage: LanguageID,
        visibleLanguage: LanguageID
    ) -> Bool {
        guard visibleLanguage == .en || visibleLanguage == .ro,
              detector.wordMatchesAlphabet(text, of: visibleLanguage) else {
            return false
        }
        return true
    }

    private func isKnownVisibleLatinWord(_ text: String, visibleLanguage: LanguageID) -> Bool {
        guard visibleLanguage == .en || visibleLanguage == .ro else { return false }
        return detector.dictionaries[visibleLanguage]?.contains(text) == true
            || detector.dictionaries[.en]?.contains(text) == true
            || detector.dictionaries[.ro]?.contains(text) == true
    }

    private func visibleTextCorrectionDecision(text: String, language: LanguageID) -> LayoutDecision {
        detector.decideVisibleTextCorrection(
            text: text,
            language: language,
            autoAddRomanianDiacritics: appState?.autoAddRomanianDiacritics == true,
            autoAddRussianYo: appState?.autoAddRussianYo == true,
            correctDoubleCapitals: appState?.correctDoubleCapitals == true,
            correctDuplicateLetters: appState?.correctDuplicateLetters == true,
            correctCommonTypos: appState?.correctCommonTypos == true,
            thresholds: currentDetectionThresholds
        )
    }

    private func applyVisibleTextCorrection(text: String, language: LanguageID, word: CommittedWord) -> Bool {
        let visibleDecision = visibleTextCorrectionDecision(text: text, language: language)
        return applyRetypeDecision(
            visibleDecision,
            word: word,
            activeLanguage: language,
            originalText: text
        )
    }

    private func applyRenderedRussianYoCorrection(text: String, word: CommittedWord) -> Bool {
        let decision = detector.decideVisibleTextCorrection(
            text: text,
            language: .ru,
            autoAddRussianYo: appState?.autoAddRussianYo == true,
            thresholds: currentDetectionThresholds
        )
        return applyRetypeDecision(
            decision,
            word: word,
            activeLanguage: .ru,
            originalText: text
        )
    }

    @discardableResult
    private func applyRetypeDecision(
        _ decision: LayoutDecision,
        word: CommittedWord,
        activeLanguage: LanguageID,
        originalText originalTextOverride: String? = nil
    ) -> Bool {
        guard let payload = decision.retypePayload else { return false }
        let corrected = payload.corrected
        let target = payload.target
        let correctionKind = payload.kind
        if activeLanguage != target,
           appState?.isLanguageDirectionEnabled(source: activeLanguage, target: target) == false {
            resetPendingSequence(clearCooldown: true)
            Self.logger.info("decision: switch suppressed (disabled direction \(activeLanguage.rawValue, privacy: .public)→\(target.rawValue, privacy: .public))")
            return true
        }
        if exclusions.contains(word.bundleID) {
            resetPendingSequence(clearCooldown: true)
            Self.logger.info("decision: switch suppressed (excluded app: \(word.bundleID ?? "?", privacy: .public))")
            return true
        }
        let originalText = originalTextOverride ?? detector.mapping.render(word.characters, in: activeLanguage)
        // Allow keycodes that render as punctuation in the active layout but
        // as letters in another (e.g. `;` → `ж`, `]` → `ъ`). decide() already
        // accepted them; double-filtering here would drop legitimate
        // wrong-layout words like `;le` (should retype to `жду`).
        let ambiguousChars = detector.mapping.ambiguousWordInternalCharacters
        guard originalText.allSatisfy({ $0.isLetter || ambiguousChars.contains($0) }) else {
            resetPendingSequence(clearCooldown: true)
            return true
        }
        if learningCache?.shouldSuppress(
            original: originalText,
            corrected: corrected,
            sourceLanguage: activeLanguage,
            targetLanguage: target,
            bundleID: word.bundleID
        ) == true {
            resetPendingSequence(clearCooldown: true)
            Self.logger.info("decision: switch suppressed (learned exception)")
            return true
        }
        let candidate = PendingRetypeCandidate(
            word: word,
            activeLanguage: activeLanguage,
            targetLanguage: target,
            corrected: corrected,
            originalText: originalText,
            correctionKind: correctionKind
        )
        guard !isRetyping else { return true }

        let extendEnabled = appState?.autoExtendRecentAmbiguous == true
        Self.logger.info("trigger: \"\(originalText, privacy: .public)\" → \"\(corrected, privacy: .public)\" target=\(target.rawValue, privacy: .public) extend=\(extendEnabled, privacy: .public) history=\(self.committedHistory.count, privacy: .public)")
        if extendEnabled {
            let retroactive = collectRetroactiveCandidates(
                currentTarget: target,
                activeLanguage: activeLanguage
            )
            if !retroactive.isEmpty {
                Self.logger.info("auto-extend: \(retroactive.count, privacy: .public) retroactive word(s) target=\(target.rawValue, privacy: .public)")
                sequenceDetector.reset()
                retypeDispatcher.dispatch(retroactive + [candidate])
                return true
            }
        }

        sequenceDetector.ingest(candidate)
        return true
    }

    /// Walks back through `committedHistory` (excluding the just-committed word) collecting
    /// not-yet-autoswitched words that, under aggressive single-char detection, agree on the
    /// same target language. Stops on any non-switching decision, autoswitched word, bundle
    /// change, non-space separator, or age beyond `autoExtendWindow`.
    private func collectRetroactiveCandidates(
        currentTarget: LanguageID,
        activeLanguage: LanguageID
    ) -> [PendingRetypeCandidate] {
        var retroactive: [PendingRetypeCandidate] = []
        let currentTime = now()
        let currentBundleID = focused.bundleID
        Self.logger.info("auto-extend scan: history=\(self.committedHistory.count, privacy: .public) currentBundle=\(currentBundleID ?? "nil", privacy: .public) target=\(currentTarget.rawValue, privacy: .public)")
        for prior in committedHistory.dropLast().reversed() {
            if retroactive.count >= tunables.autoExtendMaxRetroactiveWords {
                Self.logger.info("auto-extend stop: max words reached")
                break
            }
            let age = currentTime.timeIntervalSince(prior.committedAt)
            if age > tunables.autoExtendWindow {
                Self.logger.info("auto-extend stop: age=\(age, privacy: .public)s > window=\(self.tunables.autoExtendWindow, privacy: .public)s")
                break
            }
            if prior.bundleID != currentBundleID {
                Self.logger.info("auto-extend stop: bundle mismatch prior=\(prior.bundleID ?? "nil", privacy: .public) current=\(currentBundleID ?? "nil", privacy: .public)")
                break
            }
            if prior.separator != .space {
                Self.logger.info("auto-extend stop: separator=\(String(describing: prior.separator), privacy: .public)")
                break
            }
            let wasAutoSwitched = recents.entries.contains { entry in
                abs(entry.timestamp.timeIntervalSince(prior.committedAt)) < tunables.wasAutoSwitchedMatchWindow
            }
            if wasAutoSwitched {
                Self.logger.info("auto-extend stop: prior already auto-switched")
                break
            }
            let decision = detector.decide(
                buffer: prior.characters,
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
            guard let payload = decision.retypePayload, payload.target == currentTarget else {
                Self.logger.info("auto-extend stop: decision=\(String(describing: decision), privacy: .public)")
                break
            }
            let corrected = payload.corrected
            let target = payload.target
            let priorOriginal = detector.mapping.render(prior.characters, in: activeLanguage)
            Self.logger.info("auto-extend pick: \"\(priorOriginal, privacy: .public)\" → \"\(corrected, privacy: .public)\"")
            retroactive.append(PendingRetypeCandidate(
                word: prior,
                activeLanguage: activeLanguage,
                targetLanguage: target,
                corrected: corrected,
                originalText: priorOriginal,
                correctionKind: payload.kind
            ))
        }
        return retroactive.reversed()
    }

    /// Called when the user undoes the last auto-switch via hotkey or notification action.
    func clearUndoNotification() {
        notificationManager?.clearPendingNotification()
    }

    private func resetPendingSequence(clearCooldown: Bool = false) {
        sequenceDetector.reset()
        if clearCooldown {
            retypeDispatcher.resetCooldown()
        }
    }

    private func isSafeFinalSeparator(_ separator: WordSeparator) -> Bool {
        switch separator {
        case .space:
            return true
        case .enter, .tab:
            return false
        case .punctuation(let character):
            return tunables.safeFinalPunctuation.contains(character)
        }
    }

    /// Re-runs layout detection on the last committed word and retypes it if a different
    /// layout is detected. Delegated to `ManualActionsCoordinator`.
    func forceRetypeLastWord() {
        manualActions.forceRetypeLastWord()
    }

    /// Manual sentence-scope retype — delegated to `ManualActionsCoordinator`.
    func forceConvertLastSentence() {
        manualActions.forceConvertLastSentence()
    }

    func handle(_ event: KeyEvent) {
        switch event.kind {
        case .leftMouseDown, .rightMouseDown:
            focused.refreshSecureFieldState()
            notifyFocusContextDidChange()
            suppressUntilSeparator = false
            resetPendingSequence(clearCooldown: true)
            buffer.reset(reason: .mouseClick)
            return
        case .flagsChanged:
            return
        case .keyDown:
            break
        default:
            return
        }

        if focused.isSecureField {
            resetPendingSequence(clearCooldown: true)
            return
        }
        if let source = inputSources.current, !source.isKeyboardLayout {
            // IME active (CJK / marked-text composer): we cannot interpret raw
            // keystrokes during composition. Drop the buffer and ignore events
            // until the user switches back to a raw keyboard layout.
            suppressUntilSeparator = false
            resetPendingSequence(clearCooldown: true)
            buffer.reset(reason: .modifierShortcut)
            return
        }
        if appState?.isEnabled == false {
            // Master toggle off: passively reset on focus/click but never run detector/retyper.
            resetPendingSequence(clearCooldown: true)
            return
        }

        let cmdHeld = event.flags.contains(.maskCommand)
        // Use TokenBoundaryPolicy so punctuation-shaped keys that produce
        // letters in another supported layout (`;` → `ж`, `]` → `ъ`, etc.)
        // stay attached to the current word instead of breaking the buffer.
        let kind = TokenBoundaryPolicy(mapping: detector.mapping).classify(event)

        if cmdHeld, case .letter = kind {
            suppressUntilSeparator = false
            resetPendingSequence(clearCooldown: true)
            buffer.reset(reason: .modifierShortcut)
            return
        }

        switch kind {
        case .letter:
            guard !suppressUntilSeparator else { return }
            buffer.append(event)
        case .separator(let sep):
            if suppressUntilSeparator {
                suppressUntilSeparator = false
                buffer.reset(reason: .navigation)
                return
            }
            buffer.commit(separator: sep, separatorKeyCode: event.keyCode, separatorFlags: event.flags)
        case .backspace:
            resetPendingSequence(clearCooldown: true)
            buffer.deleteLast()
        case .navigation:
            suppressUntilSeparator = false
            resetPendingSequence(clearCooldown: true)
            buffer.reset(reason: .navigation)
        case .escape:
            suppressUntilSeparator = false
            resetPendingSequence(clearCooldown: true)
            buffer.reset(reason: .escape)
        case .digit:
            // Digits inside a word make the buffer ambiguous (versions, codes, IDs).
            // Drop the whole token until its separator so we never correct a suffix.
            suppressUntilSeparator = true
            resetPendingSequence(clearCooldown: true)
            buffer.reset(reason: .navigation)
        case .modifierOnly, .other:
            return
        }
    }
}
