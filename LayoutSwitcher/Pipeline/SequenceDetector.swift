import Foundation

/// A word that has been classified as needing layout retype but is being
/// held briefly in case more retype-eligible words follow. Multi-word bursts
/// are coalesced into a single retype block.
struct PendingRetypeCandidate {
    let word: CommittedWord
    let activeLanguage: LanguageID
    let targetLanguage: LanguageID
    let corrected: String
    let originalText: String
}

/// Sequence-detection state machine: collects pending retype candidates,
/// decides when the burst is complete (3+ words / closing punctuation /
/// 120 ms idle), and emits the drained list back to the owner for retype
/// dispatch. Cooldown enforcement is intentionally left to the owner since
/// it spans both single-word and sequence paths.
@MainActor
final class SequenceDetector {
    static let lookaheadDelay = Duration.milliseconds(120)
    static let longPauseThreshold: TimeInterval = 2.0

    private(set) var candidates: [PendingRetypeCandidate] = []
    private var flushTask: Task<Void, Never>?
    private let sleepBeforeFlush: @MainActor @Sendable (Duration) async -> Void

    /// Owner-supplied gate: detector only emits when the live word buffer is
    /// empty (the user has finished typing the current word).
    var isBufferIdle: () -> Bool = { true }

    /// Called when the detector decides a sequence is ready for retype.
    /// Owner inspects `count` and dispatches to single- vs multi-word path.
    var onFlushReady: ([PendingRetypeCandidate]) -> Void = { _ in }

    init(sleepBeforeFlush: @escaping @MainActor @Sendable (Duration) async -> Void = { duration in
        try? await Task.sleep(for: duration)
    }) {
        self.sleepBeforeFlush = sleepBeforeFlush
    }

    func ingest(_ candidate: PendingRetypeCandidate) {
        if let last = candidates.last, !canAppend(candidate, after: last) {
            reset()
        }
        candidates.append(candidate)

        if candidates.count >= 3 || isFinalSequenceSeparator(candidate.word.separator) {
            flushIfIdle()
            return
        }
        scheduleFlush()
    }

    func reset() {
        flushTask?.cancel()
        flushTask = nil
        candidates.removeAll(keepingCapacity: true)
    }

    private func canAppend(_ candidate: PendingRetypeCandidate, after previous: PendingRetypeCandidate) -> Bool {
        guard previous.word.separator == .space else { return false }
        guard candidate.word.committedAt.timeIntervalSince(previous.word.committedAt) <= Self.longPauseThreshold else {
            return false
        }
        return candidate.activeLanguage == previous.activeLanguage
            && candidate.targetLanguage == previous.targetLanguage
            && candidate.word.bundleID == previous.word.bundleID
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.sleepBeforeFlush(Self.lookaheadDelay)
            guard !Task.isCancelled else { return }
            self.flushTask = nil
            self.flushIfIdle()
        }
    }

    private func flushIfIdle() {
        guard isBufferIdle() else { return }
        let drained = candidates
        reset()
        guard !drained.isEmpty else { return }
        onFlushReady(drained)
    }

    private func isFinalSequenceSeparator(_ separator: WordSeparator) -> Bool {
        if case .punctuation = separator { return true }
        return false
    }
}
