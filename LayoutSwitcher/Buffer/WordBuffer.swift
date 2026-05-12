import CoreGraphics
import Foundation

/// One captured typed character with keycode, unicode and modifier metadata.
struct WordChar {
    let keyCode: CGKeyCode
    let unicode: String
    let flags: CGEventFlags
    let timestamp: UInt64
}

/// Snapshot of one committed token and separator context.
struct CommittedWord {
    let characters: [WordChar]
    let separator: WordSeparator
    let separatorKeyCode: CGKeyCode
    let separatorFlags: CGEventFlags
    let bundleID: String?
    let committedAt: Date

    /// Human-readable token text reconstructed from buffered unicode scalars.
    var text: String { characters.map(\.unicode).joined() }
}

/// Mutable buffer that accumulates typed characters until separator commit.
@MainActor
final class WordBuffer {
    private(set) var characters: [WordChar] = []
    private(set) var lastCommitted: CommittedWord?

    var onAppended: ((WordChar) -> Void)?
    var onCommitted: ((CommittedWord) -> Void)?
    var onReset: ((WordResetReason) -> Void)?

    /// App bundle ID supplier attached by pipeline for context-aware commits.
    var bundleIDProvider: () -> String? = { nil }

    /// Appends one key event as buffered character.
    func append(_ event: KeyEvent) {
        if characters.isEmpty {
            lastCommitted = nil
        }
        let char = WordChar(
            keyCode: event.keyCode,
            unicode: event.unicode,
            flags: event.flags,
            timestamp: event.timestamp
        )
        characters.append(char)
        onAppended?(char)
    }

    /// Removes last buffered character, if any.
    func deleteLast() {
        guard !characters.isEmpty else { return }
        characters.removeLast()
    }

    /// Finalizes current token with separator metadata and emits commit callback.
    func commit(separator: WordSeparator, separatorKeyCode: CGKeyCode = 0, separatorFlags: CGEventFlags = []) {
        guard !characters.isEmpty else { return }
        let word = CommittedWord(
            characters: characters,
            separator: separator,
            separatorKeyCode: separatorKeyCode,
            separatorFlags: separatorFlags,
            bundleID: bundleIDProvider(),
            committedAt: Date()
        )
        characters.removeAll(keepingCapacity: true)
        lastCommitted = word
        onCommitted?(word)
    }

    /// Clears current token and optionally clears last committed snapshot based on reason.
    func reset(reason: WordResetReason) {
        if clearsLastCommitted(reason) {
            lastCommitted = nil
        }
        guard !characters.isEmpty else { return }
        characters.removeAll(keepingCapacity: true)
        onReset?(reason)
    }

    /// Removes last committed snapshot without altering current typed buffer.
    func clearLastCommitted() {
        lastCommitted = nil
    }

    /// Determines whether a reset reason should invalidate undo/manual-toggle context.
    private func clearsLastCommitted(_ reason: WordResetReason) -> Bool {
        switch reason {
        case .appChanged, .mouseClick, .navigation, .escape, .modifierShortcut, .manual:
            return true
        }
    }
}
