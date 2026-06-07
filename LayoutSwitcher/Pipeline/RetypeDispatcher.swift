import Foundation
import os

/// Cooldown record keyed by `(kind, original, corrected, source, target, bundleID)` used to
/// suppress retype storms when the user keeps typing the same word.
struct AutoSwitchCooldownEntry: Sendable {
    /// Distinguishes single-token and multi-token cooldown scopes.
    enum Kind: Sendable {
        /// Cooldown for one committed word.
        case single
        /// Cooldown for a coalesced multi-word retype sequence.
        case sequence
    }

    /// Cooldown scope.
    let kind: Kind
    /// Original text before correction.
    let original: String
    /// Corrected text emitted by the detector.
    let corrected: String
    /// Language active when the original text was committed.
    let sourceLanguage: LanguageID
    /// Language selected for the correction.
    let targetLanguage: LanguageID
    /// Bundle identifier the cooldown applies to, when known.
    let bundleID: String?
    /// Expiration date after which an identical correction may run again.
    let expiresAt: Date
}

/// Executes retype operations on behalf of `TypingPipeline`. Owns the retype lifecycle:
/// cooldown suppression, async retyper invocation, post-retype analytics (stats, recents,
/// notifications, undo record, sound/visual feedback). Pipeline delegates whenever it has
/// a non-empty `[PendingRetypeCandidate]` batch ready to apply.
@MainActor
final class RetypeDispatcher {
    private static let logger = Logger(subsystem: "GM.LayoutSwitcher", category: "RetypeDispatch")

    private let retyper: Retyper
    let stats: UsageStats
    let recents: RecentSwitches
    private let notificationManager: NotificationManager?
    private let soundFeedback: SoundFeedbackPlayer?
    private let visualFeedback: VisualFeedbackPlayer?
    private let tunables: PipelineTunables
    private let bundleNameProvider: @MainActor (String) -> String?
    private let now: @MainActor () -> Date
    /// Shared application state used to honor snooze suppression.
    weak var appState: AppState?
    /// Hotkey coordinator that receives undo records after successful retypes.
    weak var hotkeyCoordinator: HotkeyCoordinator?

    /// True while a retype Task is in flight. Pipeline reads this to skip re-entry.
    private(set) var isRetyping = false
    private var cooldownEntry: AutoSwitchCooldownEntry?

    /// Wires the retype helper with all post-retype side-effect collaborators.
    init(
        retyper: Retyper,
        stats: UsageStats,
        recents: RecentSwitches,
        notificationManager: NotificationManager? = nil,
        soundFeedback: SoundFeedbackPlayer? = nil,
        visualFeedback: VisualFeedbackPlayer? = nil,
        tunables: PipelineTunables,
        bundleNameProvider: @escaping @MainActor (String) -> String? = { _ in nil },
        now: @escaping @MainActor () -> Date
    ) {
        self.retyper = retyper
        self.stats = stats
        self.recents = recents
        self.notificationManager = notificationManager
        self.soundFeedback = soundFeedback
        self.visualFeedback = visualFeedback
        self.tunables = tunables
        self.bundleNameProvider = bundleNameProvider
        self.now = now
    }

    /// Routes a candidate batch to single- vs sequence-retype paths. Honors snooze.
    func dispatch(_ candidates: [PendingRetypeCandidate]) {
        guard !candidates.isEmpty else { return }
        if appState?.isSnoozed == true {
            Self.logger.info("decision: pending auto-switch suppressed (snoozed)")
            return
        }
        if candidates.count >= 2 {
            performSequenceRetype(candidates)
        } else {
            performSingleRetype(candidates[0])
        }
    }

    /// Clears the cooldown entry (used by pipeline when context changes invalidate it).
    func resetCooldown() {
        cooldownEntry = nil
    }

    /// Allows out-of-band callers (e.g. manual force-retype paths) to reserve the
    /// retype flag and release it afterwards. Paired calls only.
    func setRetypingFlag(_ value: Bool) {
        isRetyping = value
    }

    private func performSingleRetype(_ candidate: PendingRetypeCandidate) {
        guard !isRetyping else { return }
        guard !isSuppressedByCooldown(
            kind: .single,
            original: candidate.originalText,
            corrected: candidate.corrected,
            sourceLanguage: candidate.activeLanguage,
            targetLanguage: candidate.targetLanguage,
            bundleID: candidate.word.bundleID
        ) else {
            Self.logger.info("decision: switch suppressed (single-word cooldown)")
            return
        }

        Self.logger.info("decision: switch → \"\(candidate.corrected, privacy: .public)\" target=\(candidate.targetLanguage.rawValue, privacy: .public)")
        isRetyping = true
        let word = candidate.word
        let record = AutoSwitchRecord(
            original: word.characters,
            corrected: candidate.corrected,
            targetLanguage: candidate.targetLanguage,
            sourceLanguage: candidate.activeLanguage,
            separator: word.separator,
            bundleID: word.bundleID,
            timestamp: now(),
            originalText: candidate.originalText
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRetyping = false }
            let result = await self.retyper.retypeResult(
                original: word.characters,
                corrected: candidate.corrected,
                targetLanguage: candidate.targetLanguage,
                separator: word.separator,
                separatorKeyCode: word.separatorKeyCode,
                separatorFlags: word.separatorFlags
            )
            self.recordSuccessfulRetype(
                result,
                record: record,
                original: candidate.originalText,
                corrected: candidate.corrected,
                bundleID: word.bundleID,
                cooldownKind: .single,
                correctionKind: candidate.correctionKind
            )
        }
    }

    private func performSequenceRetype(_ candidates: [PendingRetypeCandidate]) {
        guard !isRetyping, candidates.count >= 2, let last = candidates.last else { return }

        let originalText = candidates.map(\.originalText).joined(separator: " ")
        let correctedText = candidates.map(\.corrected).joined(separator: " ")
        let correctionKind = Self.sequenceCorrectionKind(candidates)
        let originalCharacters = sequenceOriginalCharacters(from: candidates)
        guard !isSuppressedByCooldown(
            kind: .sequence,
            original: originalText,
            corrected: correctedText,
            sourceLanguage: last.activeLanguage,
            targetLanguage: last.targetLanguage,
            bundleID: last.word.bundleID
        ) else {
            Self.logger.info("decision: sequence switch suppressed (multi-word cooldown)")
            return
        }

        Self.logger.info("decision: sequence switch → \"\(correctedText, privacy: .public)\" target=\(last.targetLanguage.rawValue, privacy: .public)")
        isRetyping = true
        let record = AutoSwitchRecord(
            original: originalCharacters,
            corrected: correctedText,
            targetLanguage: last.targetLanguage,
            sourceLanguage: last.activeLanguage,
            separator: last.word.separator,
            bundleID: last.word.bundleID,
            timestamp: now(),
            originalText: originalText
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRetyping = false }
            let result = await self.retyper.retypeSequenceResult(
                original: originalCharacters,
                corrected: correctedText,
                targetLanguage: last.targetLanguage,
                finalSeparator: last.word.separator,
                finalSeparatorKeyCode: last.word.separatorKeyCode,
                finalSeparatorFlags: last.word.separatorFlags
            )
            self.recordSuccessfulRetype(
                result,
                record: record,
                original: originalText,
                corrected: correctedText,
                bundleID: last.word.bundleID,
                cooldownKind: .sequence,
                correctionKind: correctionKind
            )
        }
    }

    private func recordSuccessfulRetype(
        _ result: RetypeResult,
        record: AutoSwitchRecord,
        original: String,
        corrected: String,
        bundleID: String?,
        cooldownKind: AutoSwitchCooldownEntry.Kind,
        correctionKind: CorrectionFeedbackKind
    ) {
        guard result.succeeded else {
            if case .failure(.missingRomanianLayout) = result {
                appState?.lastActionDescription = String(localized: "pipeline.result.missing-romanian-diacritics")
            }
            return
        }
        armCooldown(
            kind: cooldownKind,
            original: original,
            corrected: corrected,
            sourceLanguage: record.sourceLanguage,
            targetLanguage: record.targetLanguage,
            bundleID: bundleID
        )
        hotkeyCoordinator?.lastAutoSwitch = record
        stats.recordAutoSwitch(charactersSaved: corrected.count)
        recents.record(
            original: original,
            corrected: corrected,
            bundleID: bundleID,
            bundleName: bundleID.flatMap { bundleNameProvider($0) },
            kind: .auto,
            timestamp: now()
        )
        notificationManager?.postAutoSwitchNotification(
            original: original,
            corrected: corrected
        )
        guard let state = appState else { return }
        state.lastActionDescription = correctionKind.localizedSummary(
            original: original,
            corrected: corrected
        )
        soundFeedback?.play(
            kind: correctionKind,
            isEnabled: state.soundFeedbackEnabled
        )
        visualFeedback?.flash(kind: correctionKind, isEnabled: state.visualFeedbackEnabled)
    }

    private static func sequenceCorrectionKind(_ candidates: [PendingRetypeCandidate]) -> CorrectionFeedbackKind {
        guard let first = candidates.first else { return .layoutSwitch }
        let allSameKind = candidates.dropFirst().allSatisfy { $0.correctionKind == first.correctionKind }
        return allSameKind ? first.correctionKind : .layoutSwitch
    }

    /// Stitches per-candidate `[WordChar]` buffers with `" "` separator chars between them
    /// so the retyper can erase + retype the whole block as one continuous edit.
    private func sequenceOriginalCharacters(from candidates: [PendingRetypeCandidate]) -> [WordChar] {
        var original: [WordChar] = []
        for (index, candidate) in candidates.enumerated() {
            original.append(contentsOf: candidate.word.characters)
            if index < candidates.count - 1 {
                original.append(WordChar(
                    keyCode: candidate.word.separatorKeyCode,
                    unicode: " ",
                    flags: candidate.word.separatorFlags,
                    timestamp: candidate.word.characters.last?.timestamp ?? 0
                ))
            }
        }
        return original
    }

    private func isSuppressedByCooldown(
        kind: AutoSwitchCooldownEntry.Kind,
        original: String,
        corrected: String,
        sourceLanguage: LanguageID,
        targetLanguage: LanguageID,
        bundleID: String?
    ) -> Bool {
        guard let entry = cooldownEntry else { return false }
        let currentTime = now()
        guard currentTime < entry.expiresAt else {
            cooldownEntry = nil
            return false
        }
        return entry.kind == kind
            && entry.original == original
            && entry.corrected == corrected
            && entry.sourceLanguage == sourceLanguage
            && entry.targetLanguage == targetLanguage
            && entry.bundleID == bundleID
    }

    private func armCooldown(
        kind: AutoSwitchCooldownEntry.Kind,
        original: String,
        corrected: String,
        sourceLanguage: LanguageID,
        targetLanguage: LanguageID,
        bundleID: String?
    ) {
        cooldownEntry = AutoSwitchCooldownEntry(
            kind: kind,
            original: original,
            corrected: corrected,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            bundleID: bundleID,
            expiresAt: now().addingTimeInterval(tunables.autoSwitchCooldown)
        )
    }
}
