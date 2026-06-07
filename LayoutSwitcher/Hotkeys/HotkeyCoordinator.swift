import Foundation
import os

/// Persisted context required to undo one automatically applied switch.
struct AutoSwitchRecord: Sendable {
    let original: [WordChar]
    let corrected: String
    let targetLanguage: LanguageID
    let sourceLanguage: LanguageID
    let separator: WordSeparator
    let bundleID: String?
    let timestamp: Date
    let originalText: String?

    init(
        original: [WordChar],
        corrected: String,
        targetLanguage: LanguageID,
        sourceLanguage: LanguageID,
        separator: WordSeparator,
        bundleID: String?,
        timestamp: Date,
        originalText: String? = nil
    ) {
        self.original = original
        self.corrected = corrected
        self.targetLanguage = targetLanguage
        self.sourceLanguage = sourceLanguage
        self.separator = separator
        self.bundleID = bundleID
        self.timestamp = timestamp
        self.originalText = originalText
    }
}

/// Executes hotkey actions by orchestrating buffer state, retyping, and analytics updates.
@MainActor
final class HotkeyCoordinator {
    private static let logger = Logger(subsystem: "GM.LayoutSwitcher", category: "Hotkey")

    private let buffer: WordBuffer
    private let mapping: any KeyboardMapping
    private let retyper: Retyper
    private let inputSources: any InputSourceManaging
    private let stats: UsageStats
    private let recents: RecentSwitches
    private let appState: AppState?
    private let selectionConverter: SelectionConverter?
    private let smartPaste: SmartPaste?
    private let currentBundleIDProvider: () -> String?
    private let activeLanguageProvider: () -> LanguageID?
    private let bundleNameProvider: @MainActor (String) -> String?
    private let now: @MainActor () -> Date
    private let undoWindow: TimeInterval = 3.0
    private let manualWindow: TimeInterval = 3.0

    /// Last successful automatic switch that is still eligible for undo.
    var lastAutoSwitch: AutoSwitchRecord?
    var onSnoozeChanged: (() -> Void)?
    weak var typingPipeline: TypingPipeline?
    var forceRetypeHandler: (() -> Void)?
    private let learningCache: LearningCache?

    /// Builds coordinator with runtime dependencies and optional test hooks.
    init(
        buffer: WordBuffer,
        mapping: any KeyboardMapping,
        retyper: Retyper,
        inputSources: any InputSourceManaging,
        stats: UsageStats,
        recents: RecentSwitches,
        appState: AppState? = nil,
        selectionConverter: SelectionConverter? = nil,
        smartPaste: SmartPaste? = nil,
        learningCache: LearningCache? = nil,
        currentBundleIDProvider: @escaping () -> String? = { nil },
        activeLanguageProvider: (() -> LanguageID?)? = nil,
        bundleNameProvider: @escaping @MainActor (String) -> String? = { _ in nil },
        now: @escaping @MainActor () -> Date
    ) {
        self.buffer = buffer
        self.mapping = mapping
        self.retyper = retyper
        self.inputSources = inputSources
        self.stats = stats
        self.recents = recents
        self.appState = appState
        self.selectionConverter = selectionConverter
        self.smartPaste = smartPaste
        self.learningCache = learningCache
        self.currentBundleIDProvider = currentBundleIDProvider
        self.activeLanguageProvider = activeLanguageProvider ?? {
            LanguageID(inputSourceLanguageCode: inputSources.current?.primaryLanguage)
        }
        self.bundleNameProvider = bundleNameProvider
        self.now = now
    }

    /// Routes incoming hotkey action to its async handler.
    func handle(_ action: HotkeyAction) {
        switch action {
        case .manualToggleLast:
            Task { @MainActor [weak self] in await self?.manualToggle() }
        case .undoLastAutoSwitch:
            Task { @MainActor [weak self] in await self?.undoLastSwitch() }
        case .convertSelection:
            Task { @MainActor [weak self] in await self?.convertSelection() }
        case .cycleSelectionCase:
            Task { @MainActor [weak self] in await self?.cycleSelectionCase() }
        case .snooze:
            toggleSnooze()
        case .forceRetypeLastWord:
            if let handler = forceRetypeHandler {
                handler()
            } else {
                typingPipeline?.forceRetypeLastWord()
            }
        case .convertLastSentence:
            typingPipeline?.forceConvertLastSentence()
        case .smartPaste:
            Task { @MainActor [weak self] in await self?.runSmartPaste() }
        case .expandAutoReplace:
            typingPipeline?.expandCurrentWordViaHotkey()
        }
    }

    /// Routes ⌃⌥⌘V to the SmartPaste helper. Logs result and updates last-action text.
    private func runSmartPaste() async {
        guard let smartPaste else {
            Self.logger.error("smartPaste: helper is not configured")
            return
        }
        let result = await smartPaste.paste()
        Self.logger.info("smartPaste result=\(String(describing: result), privacy: .public)")
        if case .pasted(_, let switched) = result, switched {
            stats.recordManualSwitch()
        }
    }

    private func toggleSnooze() {
        guard let appState else {
            Self.logger.error("snooze: app state is not configured")
            return
        }
        if appState.isSnoozed {
            appState.clearSnooze()
            Self.logger.info("snooze cleared")
        } else {
            appState.startSnooze()
            Self.logger.info("snooze started for \(appState.snoozeDuration.rawValue, privacy: .public)m")
        }
        onSnoozeChanged?()
    }

    /// Manually toggles last committed word between RU and EN keyboard rendering.
    private func manualToggle() async {
        guard let last = buffer.lastCommitted else {
            Self.logger.info("manualToggle: no last committed word")
            return
        }
        guard now().timeIntervalSince(last.committedAt) <= manualWindow else {
            Self.logger.info("manualToggle: last committed word expired")
            buffer.clearLastCommitted()
            return
        }
        if let committedBundleID = last.bundleID,
           let currentBundleID = currentBundleIDProvider(),
           committedBundleID != currentBundleID {
            Self.logger.info("manualToggle: focused app changed from \(committedBundleID, privacy: .public) to \(currentBundleID, privacy: .public)")
            buffer.clearLastCommitted()
            return
        }
        guard let activeLanguage = activeLanguageProvider() else {
            return
        }
        let target: LanguageID = toggleTargetLanguage(for: activeLanguage)
        let corrected = mapping.render(last.characters, in: target)
        guard !corrected.isEmpty else { return }
        Self.logger.info("manualToggle → \"\(corrected, privacy: .public)\" target=\(target.rawValue, privacy: .public)")
        let succeeded = await retyper.retype(
            original: last.characters,
            corrected: corrected,
            targetLanguage: target,
            separator: last.separator,
            separatorKeyCode: last.separatorKeyCode,
            separatorFlags: last.separatorFlags
        )
        guard succeeded else { return }
        stats.recordManualSwitch()
        recents.record(
            original: last.text,
            corrected: corrected,
            bundleID: last.bundleID,
            bundleName: last.bundleID.flatMap { bundleNameProvider($0) },
            kind: .manual,
            timestamp: now()
        )
    }

    /// Returns paired manual-toggle target language for a given active layout.
    private func toggleTargetLanguage(for activeLanguage: LanguageID) -> LanguageID {
        switch activeLanguage {
        case .en:
            return .ru
        case .ru, .uk, .ro:
            return .en
        }
    }

    /// Replays opposite text for latest auto-switch when inside undo window and same app context.
    private func undoLastSwitch() async {
        guard let record = lastAutoSwitch else {
            Self.logger.info("undoLastSwitch: nothing to undo")
            return
        }
        guard now().timeIntervalSince(record.timestamp) <= undoWindow else {
            Self.logger.info("undoLastSwitch: undo window expired")
            lastAutoSwitch = nil
            return
        }
        if record.bundleID != currentBundleIDProvider() {
            Self.logger.info("undoLastSwitch: bundle mismatch, skipping (recorded=\(record.bundleID ?? "?", privacy: .public) current=\(self.currentBundleIDProvider() ?? "?", privacy: .public))")
            lastAutoSwitch = nil
            return
        }
        let originalText = record.originalText ?? mapping.render(record.original, in: record.sourceLanguage)
        Self.logger.info("undoLastSwitch → \"\(originalText, privacy: .public)\" target=\(record.sourceLanguage.rawValue, privacy: .public)")

        // The buffer of synthetic chars to "erase" is the corrected word we typed previously.
        let syntheticChars = record.corrected.map { _ in
            WordChar(keyCode: 0, unicode: "", flags: [], timestamp: 0)
        }
        let success = await retyper.retype(
            original: syntheticChars,
            corrected: originalText,
            targetLanguage: record.sourceLanguage,
            separator: record.separator
        )
        if success {
            learningCache?.recordUndo(record: record)
            typingPipeline?.clearUndoNotification()
        }
        lastAutoSwitch = nil
    }

    /// Cycles the selected text's letter case via the isolated selection converter.
    private func cycleSelectionCase() async {
        guard let selectionConverter else {
            Self.logger.error("cycleSelectionCase: converter is not configured")
            return
        }
        let changed = await selectionConverter.cycleSelectionCase()
        Self.logger.info("cycleSelectionCase changed=\(changed, privacy: .public)")
    }

    /// Converts current user-selected text through the isolated selection converter.
    private func convertSelection() async {
        guard let selectionConverter else {
            Self.logger.error("convertSelection: converter is not configured")
            return
        }
        let result = await selectionConverter.convertSelection()
        switch result {
        case .success(let conversion, let method):
            Self.logger.info("convertSelection succeeded method=\(String(describing: method), privacy: .public) source=\(conversion.sourceLanguage.rawValue, privacy: .public) target=\(conversion.targetLanguage.rawValue, privacy: .public)")
            stats.recordManualSwitch()
            recents.record(
                original: conversion.sourceText,
                corrected: conversion.convertedText,
                bundleID: currentBundleIDProvider(),
                bundleName: currentBundleIDProvider().flatMap { bundleNameProvider($0) },
                kind: .manual,
                timestamp: now()
            )
        case .failure(let reason):
            Self.logger.info("convertSelection skipped: \(String(describing: reason), privacy: .public)")
        }
    }
}
