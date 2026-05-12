import AppKit
import CoreGraphics
import Carbon.HIToolbox
import os

struct RetypeInputSource: Equatable {
    let id: String
    let primaryLanguage: String?
    fileprivate let source: InputSource?
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

    fileprivate init(_ source: InputSource) {
        self.id = source.id
        self.primaryLanguage = source.primaryLanguage
        self.source = source
        self.layoutData = source.unicodeKeyLayoutData()
    }
}

enum RetypeFailureReason: Equatable {
    case emptyInput
    case missingRomanianLayout
    case missingTargetLayout(LanguageID)
    case unencodableCharacter(String, LanguageID)
    case selectLayoutFailed(String, OSStatus)
    case layoutConfirmationTimedOut(String)
}

enum RetypeResult: Equatable {
    case success
    case failure(RetypeFailureReason)

    var succeeded: Bool {
        if case .success = self { return true }
        return false
    }
}

@MainActor
final class Retyper {
    static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "Retyper")

    private let mapping: any KeyboardMapping
    private let enabledLayoutsProvider: () -> [RetypeInputSource]
    private let currentLayoutIDProvider: () -> String?
    private let refreshCurrentLayout: () -> Void
    private let selectLayout: (RetypeInputSource) -> OSStatus
    private let sleep: (UInt64) async -> Void
    private let postKeyEvent: (CGKeyCode, CGEventFlags) -> Void
    private let postUnicodeEvent: (String) -> Void
    private let capsLockGuard: CapsLockGuard

    init(
        mapping: any KeyboardMapping,
        inputSources: any InputSourceManaging,
        enabledLayoutsProvider: (() -> [RetypeInputSource])? = nil,
        currentLayoutIDProvider: (() -> String?)? = nil,
        refreshCurrentLayout: (() -> Void)? = nil,
        selectLayout: ((RetypeInputSource) -> OSStatus)? = nil,
        sleep: ((UInt64) async -> Void)? = nil,
        postKeyEvent: ((CGKeyCode, CGEventFlags) -> Void)? = nil,
        postUnicodeEvent: ((String) -> Void)? = nil,
        capsLockGuard: CapsLockGuard? = nil
    ) {
        self.mapping = mapping
        self.enabledLayoutsProvider = enabledLayoutsProvider ?? {
            inputSources.enabledLayouts().map(RetypeInputSource.init)
        }
        self.currentLayoutIDProvider = currentLayoutIDProvider ?? {
            inputSources.current?.id
        }
        self.refreshCurrentLayout = refreshCurrentLayout ?? {
            inputSources.refresh()
        }
        self.selectLayout = selectLayout ?? { layout in
            guard let source = layout.source else { return OSStatus(paramErr) }
            return inputSources.select(source)
        }
        self.sleep = sleep ?? { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
        self.postKeyEvent = postKeyEvent ?? { keyCode, flags in
            Self.postKey(keyCode: keyCode, flags: flags)
        }
        self.postUnicodeEvent = postUnicodeEvent ?? { text in
            Self.postUnicode(text)
        }
        self.capsLockGuard = capsLockGuard ?? CapsLockGuard()
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

    private static func postKey(keyCode: CGKeyCode, flags: CGEventFlags = []) {
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

    private static func postUnicode(_ text: String) {
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
