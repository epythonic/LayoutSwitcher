import AppKit
import CoreGraphics
import Carbon.HIToolbox
import os

/// Keyboard input-source metadata used during synthetic retyping.
///
/// Test fixtures use identifier-only instances, while production instances may
/// carry a live `InputSource` reference and cached keyboard layout data.
struct RetypeInputSource: Equatable {
    /// Stable system identifier for the keyboard input source.
    let id: String
    /// Primary language reported by the input source, when available.
    let primaryLanguage: String?
    /// Live system input source used only on the main actor for selection.
    let source: InputSource?
    /// Cached Unicode key layout data used to encode target characters.
    fileprivate let layoutData: Data?

    init(id: String, primaryLanguage: String?) {
        self.id = id
        self.primaryLanguage = primaryLanguage
        self.source = nil
        self.layoutData = nil
    }

    init(id: String, primaryLanguage: String?, layoutData: Data?) {
        self.id = id
        self.primaryLanguage = primaryLanguage
        self.source = nil
        self.layoutData = layoutData
    }

    init(_ source: InputSource) {
        self.id = source.id
        self.primaryLanguage = source.primaryLanguage
        self.source = source
        self.layoutData = source.unicodeKeyLayoutData()
    }
}

/// Explicit domain failure reasons for retype operations.
///
/// Failures are returned as data instead of thrown so callers can record,
/// test, and branch on expected recoverable outcomes.
enum RetypeFailureReason: Equatable, Sendable {
    /// The original token contains no characters to replace.
    case emptyInput
    /// Romanian diacritic correction was requested but no Romanian layout is enabled.
    case missingRomanianLayout
    /// No enabled layout matches the requested target language.
    case missingTargetLayout(LanguageID)
    /// A character could not be represented in the target layout.
    case unencodableCharacter(String, LanguageID)
    /// Selecting the target input source failed with a system status code.
    case selectLayoutFailed(String, OSStatus)
    /// The selected layout did not become current before the confirmation timeout.
    case layoutConfirmationTimedOut(String)
}

/// Result of a synthetic retype attempt.
enum RetypeResult: Equatable, Sendable {
    /// The retype completed and synthetic input was emitted.
    case success
    /// The retype stopped before destructive input because a recoverable issue was detected.
    case failure(RetypeFailureReason)

    /// Convenience flag used by legacy boolean call sites.
    var succeeded: Bool {
        if case .success = self { return true }
        return false
    }
}

/// Performs safe synthetic retyping after a target keyboard layout is selected.
///
/// The retyper avoids destructive input until the target layout is available and
/// confirmed. All side effects are injected so tests can exercise layout
/// selection, timing, and event posting deterministically.
@MainActor
struct Retyper {
    static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "Retyper")

    private let mapping: any KeyboardMapping
    private let enabledLayoutsProvider: @MainActor () -> [RetypeInputSource]
    private let currentLayoutIDProvider: @MainActor () -> String?
    private let refreshCurrentLayout: @MainActor () -> Void
    private let selectLayout: @MainActor (RetypeInputSource) -> OSStatus
    private let sleep: @MainActor (UInt64) async -> Void
    private let postKeyEvent: @MainActor (CGKeyCode, CGEventFlags) -> Void
    private let postUnicodeEvent: @MainActor (String) -> Void
    private let capsLockGuard: CapsLockGuard

    /// Creates a retyper with all side effects injected by the composition root.
    init(
        mapping: any KeyboardMapping,
        enabledLayoutsProvider: @escaping @MainActor () -> [RetypeInputSource],
        currentLayoutIDProvider: @escaping @MainActor () -> String?,
        refreshCurrentLayout: @escaping @MainActor () -> Void,
        selectLayout: @escaping @MainActor (RetypeInputSource) -> OSStatus,
        sleep: @escaping @MainActor (UInt64) async -> Void,
        postKeyEvent: @escaping @MainActor (CGKeyCode, CGEventFlags) -> Void,
        postUnicodeEvent: @escaping @MainActor (String) -> Void,
        capsLockGuard: CapsLockGuard
    ) {
        self.mapping = mapping
        self.enabledLayoutsProvider = enabledLayoutsProvider
        self.currentLayoutIDProvider = currentLayoutIDProvider
        self.refreshCurrentLayout = refreshCurrentLayout
        self.selectLayout = selectLayout
        self.sleep = sleep
        self.postKeyEvent = postKeyEvent
        self.postUnicodeEvent = postUnicodeEvent
        self.capsLockGuard = capsLockGuard
    }

    /// Erase original word + separator, switch to target layout, type corrected word + separator.
    /// Returns `true` if the operation completed; `false` aborts before any destructive action.
    @discardableResult
    func retype(
        original: [WordChar],
        corrected: String,
        targetLanguage: LanguageID,
        separator: WordSeparator,
        separatorKeyCode: CGKeyCode = 0,
        separatorFlags: CGEventFlags = []
    ) async -> Bool {
        await retypeResult(
            original: original,
            corrected: corrected,
            targetLanguage: targetLanguage,
            separator: separator,
            separatorKeyCode: separatorKeyCode,
            separatorFlags: separatorFlags
        ).succeeded
    }

    @discardableResult
    func retypeResult(
        original: [WordChar],
        corrected: String,
        targetLanguage: LanguageID,
        separator: WordSeparator,
        separatorKeyCode: CGKeyCode = 0,
        separatorFlags: CGEventFlags = []
    ) async -> RetypeResult {
        guard !original.isEmpty, !corrected.isEmpty else { return .failure(.emptyInput) }

        // ─── PREFLIGHT (no destructive actions yet) ──────────────────────────────
        let layouts = enabledLayoutsProvider()
        let requiresRomanianLayout = targetLanguage == .ro && RomanianDiacriticResolver.containsRomanianDiacritic(corrected)
        let targetSource: RetypeInputSource? = {
            if let exact = layouts.first(where: { ($0.primaryLanguage ?? "").lowercased().hasPrefix(targetLanguage.rawValue) }) {
                return exact
            }
            if targetLanguage == .ro,
               !requiresRomanianLayout,
               let englishLayout = layouts.first(where: { ($0.primaryLanguage ?? "").lowercased().hasPrefix("en") }) {
                Self.logger.notice("Romanian layout not enabled — using English layout for retype")
                return englishLayout
            }
            return nil
        }()
        guard let targetSource else {
            Self.logger.error("No enabled layout for target=\(targetLanguage.rawValue, privacy: .public); aborting before any erase")
            if requiresRomanianLayout {
                return .failure(.missingRomanianLayout)
            }
            return .failure(.missingTargetLayout(targetLanguage))
        }

        // 2. Pre-encode every character of `corrected`. If we can't represent any of
        //    them on the target layout, we must NOT erase anything.
        var encoded: [EncodedKey] = []
        encoded.reserveCapacity(corrected.count)
        for character in corrected {
            guard let pair = encode(character, targetSource: targetSource, targetLanguage: targetLanguage) else {
                Self.logger.error("Cannot encode character \"\(String(character), privacy: .public)\" on \(targetLanguage.rawValue, privacy: .public); aborting before any erase")
                return .failure(.unencodableCharacter(String(character), targetLanguage))
            }
            encoded.append(pair)
        }

        // 3. Determine separator handling. Printable punctuation is inserted as
        //    Unicode after the layout switch so it is not reinterpreted as a target
        //    layout key.
        enum SeparatorOutput {
            case key(CGKeyCode, flags: CGEventFlags)
            case unicode(String)
        }

        let separatorOutput: SeparatorOutput? = {
            switch separator {
            case .space: return .key(49, flags: [])
            case .enter: return .key(36, flags: [])
            case .tab:   return .key(48, flags: [])
            case .punctuation(let character):
                return .unicode(String(character))
            }
        }()

        Self.logger.info("retype original=\(original.count, privacy: .public) corrected=\"\(corrected, privacy: .public)\" target=\(targetLanguage.rawValue, privacy: .public)")

        // Select and confirm the target layout before any destructive edit.
        if currentLayoutIDProvider() != targetSource.id {
            let status = selectLayout(targetSource)
            guard status == noErr else {
                Self.logger.error("Failed to select layout \(targetSource.id, privacy: .public): \(status, privacy: .public); aborting before any erase")
                return .failure(.selectLayoutFailed(targetSource.id, status))
            }
            guard await waitForLayout(targetSource.id) else {
                Self.logger.error("Timed out waiting for layout \(targetSource.id, privacy: .public); aborting before any erase")
                return .failure(.layoutConfirmationTimedOut(targetSource.id))
            }
        }

        // ─── DESTRUCTIVE PHASE ───────────────────────────────────────────────────
        capsLockGuard.captureAndDisable()
        defer { capsLockGuard.restore() }

        let charsToErase = original.count + 1
        for _ in 0..<charsToErase {
            postKeyEvent(51, []) // backspace
        }

        for entry in encoded {
            postKeyEvent(entry.keyCode, entry.flags)
        }

        if let separatorOutput {
            switch separatorOutput {
            case .key(let key, let flags):
                var outputFlags = flags
                if separatorFlags.contains(.maskShift) {
                    outputFlags.insert(.maskShift)
                }
                postKeyEvent(key, outputFlags)
            case .unicode(let text):
                postUnicodeEvent(text)
            }
        }
        return .success
    }

    /// Erase original block + final separator, then type corrected text with internal spaces.
    @discardableResult
    func retypeSequenceResult(
        original: [WordChar],
        corrected: String,
        targetLanguage: LanguageID,
        finalSeparator: WordSeparator,
        finalSeparatorKeyCode: CGKeyCode = 0,
        finalSeparatorFlags: CGEventFlags = []
    ) async -> RetypeResult {
        guard !original.isEmpty, !corrected.isEmpty else { return .failure(.emptyInput) }

        let layouts = enabledLayoutsProvider()
        let requiresRomanianLayout = targetLanguage == .ro && RomanianDiacriticResolver.containsRomanianDiacritic(corrected)
        let targetSource: RetypeInputSource? = {
            if let exact = layouts.first(where: { ($0.primaryLanguage ?? "").lowercased().hasPrefix(targetLanguage.rawValue) }) {
                return exact
            }
            if targetLanguage == .ro,
               !requiresRomanianLayout,
               let englishLayout = layouts.first(where: { ($0.primaryLanguage ?? "").lowercased().hasPrefix("en") }) {
                Self.logger.notice("Romanian layout not enabled — using English layout for sequence retype")
                return englishLayout
            }
            return nil
        }()
        guard let targetSource else {
            Self.logger.error("No enabled layout for target=\(targetLanguage.rawValue, privacy: .public); aborting sequence before any erase")
            if requiresRomanianLayout {
                return .failure(.missingRomanianLayout)
            }
            return .failure(.missingTargetLayout(targetLanguage))
        }

        var encoded: [EncodedKey] = []
        encoded.reserveCapacity(corrected.count)
        for character in corrected {
            if character == " " {
                encoded.append(EncodedKey(keyCode: 49, flags: []))
                continue
            }
            guard let pair = encode(character, targetSource: targetSource, targetLanguage: targetLanguage) else {
                Self.logger.error("Cannot encode sequence character \"\(String(character), privacy: .public)\" on \(targetLanguage.rawValue, privacy: .public); aborting before any erase")
                return .failure(.unencodableCharacter(String(character), targetLanguage))
            }
            encoded.append(pair)
        }

        enum SeparatorOutput {
            case key(CGKeyCode, flags: CGEventFlags)
            case unicode(String)
        }

        let separatorOutput: SeparatorOutput? = {
            switch finalSeparator {
            case .space: return .key(49, flags: [])
            case .enter: return .key(36, flags: [])
            case .tab:   return .key(48, flags: [])
            case .punctuation(let character):
                return .unicode(String(character))
            }
        }()

        Self.logger.info("retype sequence original=\(original.count, privacy: .public) corrected=\"\(corrected, privacy: .public)\" target=\(targetLanguage.rawValue, privacy: .public)")

        if currentLayoutIDProvider() != targetSource.id {
            let status = selectLayout(targetSource)
            guard status == noErr else {
                Self.logger.error("Failed to select layout \(targetSource.id, privacy: .public): \(status, privacy: .public); aborting sequence before any erase")
                return .failure(.selectLayoutFailed(targetSource.id, status))
            }
            guard await waitForLayout(targetSource.id) else {
                Self.logger.error("Timed out waiting for layout \(targetSource.id, privacy: .public); aborting sequence before any erase")
                return .failure(.layoutConfirmationTimedOut(targetSource.id))
            }
        }

        capsLockGuard.captureAndDisable()
        defer { capsLockGuard.restore() }

        let charsToErase = original.count + 1
        for _ in 0..<charsToErase {
            postKeyEvent(51, [])
        }

        for entry in encoded {
            postKeyEvent(entry.keyCode, entry.flags)
        }

        if let separatorOutput {
            switch separatorOutput {
            case .key(let key, let flags):
                var outputFlags = flags
                if finalSeparatorFlags.contains(.maskShift) {
                    outputFlags.insert(.maskShift)
                }
                postKeyEvent(key, outputFlags)
            case .unicode(let text):
                postUnicodeEvent(text)
            }
        }
        return .success
    }

    private func encode(
        _ character: Character,
        targetSource: RetypeInputSource,
        targetLanguage: LanguageID
    ) -> EncodedKey? {
        if let layoutData = targetSource.layoutData,
           let encoded = KeyCodeEncoder.encode(character, layoutData: layoutData) {
            return encoded
        }
        guard let fallback = mapping.keyCode(for: character, language: targetLanguage) else {
            return nil
        }
        var flags: CGEventFlags = []
        if fallback.shift {
            flags.insert(.maskShift)
        }
        return EncodedKey(keyCode: fallback.keyCode, flags: flags)
    }

    private func waitForLayout(_ id: String, timeoutNanoseconds: UInt64 = 200_000_000) async -> Bool {
        let step: UInt64 = 10_000_000
        var elapsed: UInt64 = 0
        while elapsed <= timeoutNanoseconds {
            refreshCurrentLayout()
            if currentLayoutIDProvider() == id {
                return true
            }
            await sleep(step)
            elapsed += step
        }
        refreshCurrentLayout()
        return currentLayoutIDProvider() == id
    }

    static func postKey(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        down.flags = flags
        up.flags = flags
        SyntheticEventFilter.tag(down)
        SyntheticEventFilter.tag(up)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    static func postUnicode(_ text: String) {
        guard !text.isEmpty else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return
        }
        let utf16 = Array(text.utf16)
        utf16.withUnsafeBufferPointer { buffer in
            down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
        }
        SyntheticEventFilter.tag(down)
        SyntheticEventFilter.tag(up)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
