import AppKit
import CoreGraphics
import Foundation
import os

/// Hot-key paste action that aligns the destination input source with the language
/// of the clipboard before issuing ⌘V. Subsequent typing then continues in the
/// expected layout without a manual switch.
@MainActor
struct SmartPaste {
    private static let logger = Logger(subsystem: "GM.LayoutSwitcher", category: "SmartPaste")
    private static let maxClipboardLength = SelectionTextConverter.absoluteMaxSelectionLength

    private let inputSources: any InputSourceManaging
    private let pasteboardRead: @MainActor () -> String?
    private let postKeyEvent: @MainActor (CGKeyCode, CGEventFlags) -> Void
    private let sleep: @MainActor (UInt64) async -> Void

    enum Result: Equatable, Sendable {
        case pasted(language: LanguageID, layoutSwitched: Bool)
        case clipboardEmpty
        case tooLong
    }

    /// Creates smart paste with explicit side-effect collaborators.
    init(
        inputSources: any InputSourceManaging,
        pasteboardRead: @escaping @MainActor () -> String?,
        postKeyEvent: @escaping @MainActor (CGKeyCode, CGEventFlags) -> Void,
        sleep: @escaping @MainActor (UInt64) async -> Void
    ) {
        self.inputSources = inputSources
        self.pasteboardRead = pasteboardRead
        self.postKeyEvent = postKeyEvent
        self.sleep = sleep
    }

    /// Posts one synthetic key press tagged for event-tap filtering.
    static func postKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return
        }
        down.flags = flags
        up.flags = flags
        SyntheticEventFilter.tag(down)
        SyntheticEventFilter.tag(up)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Reads clipboard, picks the layout matching its language, posts ⌘V.
    func paste() async -> Result {
        guard let clipboard = pasteboardRead(), !clipboard.isEmpty else {
            return .clipboardEmpty
        }
        guard clipboard.count <= Self.maxClipboardLength else {
            return .tooLong
        }

        let targetLanguage = detectLanguage(clipboard)
        let layoutSwitched = selectLayout(for: targetLanguage)
        if layoutSwitched {
            // Give TIS a moment to propagate before the synthetic ⌘V is posted.
            await sleep(40_000_000)
        }

        postKeyEvent(9, [.maskCommand]) // ⌘V
        await sleep(20_000_000)

        Self.logger.info("smart-paste lang=\(targetLanguage.rawValue, privacy: .public) switched=\(layoutSwitched, privacy: .public)")
        return .pasted(language: targetLanguage, layoutSwitched: layoutSwitched)
    }

    /// Selects the first enabled input source whose primary language matches the target.
    /// Returns true if the layout actually changed.
    private func selectLayout(for language: LanguageID) -> Bool {
        let languageCode = language.rawValue
        if inputSources.current?.primaryLanguage == languageCode { return false }
        guard let target = inputSources.enabledLayouts().first(where: { $0.primaryLanguage == languageCode }) else {
            return false
        }
        let status = inputSources.select(target)
        if status == noErr {
            inputSources.refresh()
            return true
        }
        Self.logger.error("smart-paste: TISSelectInputSource failed status=\(status, privacy: .public)")
        return false
    }

    /// Detects content language by Unicode script — Ukrainian-specific glyphs first,
    /// then any Cyrillic → Russian, then Romanian diacritics → Romanian, else English.
    private func detectLanguage(_ text: String) -> LanguageID {
        let ukrainianGlyphs: Set<Character> = ["і", "ї", "є", "ґ", "І", "Ї", "Є", "Ґ"]
        if text.contains(where: { ukrainianGlyphs.contains($0) }) {
            return .uk
        }
        let cyrillicRange: ClosedRange<Unicode.Scalar> = "\u{0400}"..."\u{04FF}"
        if text.unicodeScalars.contains(where: { cyrillicRange.contains($0) }) {
            return .ru
        }
        let romanianMarkers: Set<Character> = ["ă", "â", "î", "ș", "ț", "Ă", "Â", "Î", "Ș", "Ț"]
        if text.contains(where: { romanianMarkers.contains($0) }) {
            return .ro
        }
        return .en
    }
}
