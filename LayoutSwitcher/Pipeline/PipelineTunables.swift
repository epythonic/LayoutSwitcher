import Foundation

/// Centralized tuning knobs for `TypingPipeline` and its helpers — windows, caps,
/// and punctuation classes that previously lived as scattered `private static let`
/// constants. Grouping them here makes intent visible from one place and allows
/// tests / experiments to vary values without touching the pipeline source.
struct PipelineTunables: Sendable {
    // MARK: - Cooldown & history

    /// Time window during which a successful auto-switch with identical
    /// `(original, corrected, source, target, bundleID)` is suppressed to
    /// prevent retype storms when the user keeps typing the same word.
    var autoSwitchCooldown: TimeInterval = 1.5

    /// Hard cap on `committedHistory` length; the buffer is FIFO-trimmed beyond this.
    var maxCommittedHistory: Int = 20

    /// Look-back window for matching a `RecentSwitchEntry` to a committed word
    /// when deciding whether the word was already auto-switched.
    var wasAutoSwitchedMatchWindow: TimeInterval = 0.5

    // MARK: - Manual sentence convert

    /// Maximum age of the trailing committed word eligible for manual
    /// sentence convert (older words are out of scope).
    var sentenceConvertMaxAge: TimeInterval = 60

    /// Hard cap on the number of words collected when walking back to the
    /// nearest sentence boundary.
    var sentenceConvertMaxWords: Int = 20

    /// Punctuation separators that DO NOT block auto-switch (safe to retype
    /// without losing user input). Tab/Enter live in their own kind and are
    /// always considered unsafe.
    var safeFinalPunctuation: Set<Character> = Set(".,!?;:)")

    /// Characters that close a "sentence" for manual sentence-convert traversal:
    /// crossing one of these stops the walk back through `committedHistory`.
    var sentenceEndingPunctuation: Set<Character> = Set(".!?")

    // MARK: - Auto-extend retroactive

    /// Time window in which an ambiguous prior word is still considered part of
    /// the active typing burst and may be swallowed by auto-extension.
    var autoExtendWindow: TimeInterval = 2.0

    /// Hard cap on how many ambiguous prior words auto-extension will pull in.
    var autoExtendMaxRetroactiveWords: Int = 4

    /// Baseline tunables used when callers don't supply an explicit override.
    nonisolated static let `default` = PipelineTunables()
}
