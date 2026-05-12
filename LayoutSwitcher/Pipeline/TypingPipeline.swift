import CoreGraphics
import Foundation
import os

@MainActor
final class TypingPipeline {
    private static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "Pipeline")
    let tunables: PipelineTunables

    private let buffer: WordBuffer
    private let focused: FocusedAppObserver
    private let detector: LayoutDetector
    private let retyper: Retyper
    private let inputSources: any InputSourceManaging
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
        tunables: PipelineTunables = .default,
        sleepBeforeSequenceFlush: @escaping @MainActor @Sendable (Duration) async -> Void = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        self.buffer = buffer
        self.focused = focused
        self.detector = detector
        self.retyper = retyper
        self.inputSources = inputSources
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
            tunables: tunables
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
            committedHistoryProvider: { historyProvider() }
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

        let decision = detector.decide(
            buffer: word.characters,
            activeLanguage: activeLanguage,
            autoAddRomanianDiacritics: appState?.autoAddRomanianDiacritics == true,
            correctSingleCharacterWords: appState?.correctSingleCharacterWords == true
        )
        switch decision {
        case .keep:
            resetPendingSequence(clearCooldown: true)
            return
        case .ambiguous(let reason):
            resetPendingSequence(clearCooldown: true)
            Self.logger.debug("ambiguous: \(reason, privacy: .public)")
        case .switchAndRetype(let corrected, let target):
            if exclusions.contains(word.bundleID) {
                resetPendingSequence(clearCooldown: true)
                Self.logger.info("decision: switch suppressed (excluded app: \(word.bundleID ?? "?", privacy: .public))")
                return
            }
            let originalText = detector.mapping.render(word.characters, in: activeLanguage)
            // Allow keycodes that render as punctuation in the active layout but
            // as letters in another (e.g. `;` → `ж`, `]` → `ъ`). decide() already
            // accepted them; double-filtering here would drop legitimate
            // wrong-layout words like `;le` (should retype to `жду`).
            let ambiguousChars = detector.mapping.ambiguousWordInternalCharacters
            guard originalText.allSatisfy({ $0.isLetter || ambiguousChars.contains($0) }) else {
                resetPendingSequence(clearCooldown: true)
                return
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
                return
            }
            let candidate = PendingRetypeCandidate(
                word: word,
                activeLanguage: activeLanguage,
                targetLanguage: target,
                corrected: corrected,
                originalText: originalText
            )
            guard !isRetyping else { return }

            if appState?.autoExtendRecentAmbiguous == true {
                let retroactive = collectRetroactiveCandidates(
                    currentTarget: target,
                    activeLanguage: activeLanguage
                )
                if !retroactive.isEmpty {
                    Self.logger.info("auto-extend: \(retroactive.count, privacy: .public) retroactive word(s) target=\(target.rawValue, privacy: .public)")
                    sequenceDetector.reset()
                    retypeDispatcher.dispatch(retroactive + [candidate])
                    return
                }
            }

            sequenceDetector.ingest(candidate)
        }
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
        let now = Date()
        let currentBundleID = focused.bundleID
        for prior in committedHistory.dropLast().reversed() {
            if retroactive.count >= tunables.autoExtendMaxRetroactiveWords { break }
            if now.timeIntervalSince(prior.committedAt) > tunables.autoExtendWindow { break }
            if prior.bundleID != currentBundleID { break }
            if prior.separator != .space { break }
            let wasAutoSwitched = recents.entries.contains { entry in
                abs(entry.timestamp.timeIntervalSince(prior.committedAt)) < tunables.wasAutoSwitchedMatchWindow
            }
            if wasAutoSwitched { break }
            let decision = detector.decide(
                buffer: prior.characters,
                activeLanguage: activeLanguage,
                autoAddRomanianDiacritics: appState?.autoAddRomanianDiacritics == true,
                correctSingleCharacterWords: true
            )
            guard case .switchAndRetype(let corrected, let target) = decision, target == currentTarget else {
                break
            }
            let priorOriginal = detector.mapping.render(prior.characters, in: activeLanguage)
            retroactive.append(PendingRetypeCandidate(
                word: prior,
                activeLanguage: activeLanguage,
                targetLanguage: target,
                corrected: corrected,
                originalText: priorOriginal
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
