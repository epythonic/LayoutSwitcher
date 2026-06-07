import ApplicationServices
import CoreGraphics
import Foundation
import os

/// Performs manual "convert selected text" through Accessibility first, then clipboard.
@MainActor
struct SelectionConverter {
    private static let logger = Logger(subsystem: "GM.LayoutSwitcher", category: "SelectionConverter")

    private let textConverter: SelectionTextConverter
    private let focused: FocusedAppObserving
    private let focusedElementProvider: @MainActor () -> AXUIElement?
    private let pasteboardRead: @MainActor () -> String?
    private let pasteboardWrite: @MainActor (String) -> Void
    private let postKeyEvent: @MainActor (CGKeyCode, CGEventFlags) -> Void
    private let sleep: @MainActor (UInt64) async -> Void

    /// Creates converter with explicit Accessibility, pasteboard and keyboard side effects.
    init(
        textConverter: SelectionTextConverter,
        focused: FocusedAppObserving,
        focusedElementProvider: @escaping @MainActor () -> AXUIElement?,
        pasteboardRead: @escaping @MainActor () -> String?,
        pasteboardWrite: @escaping @MainActor (String) -> Void,
        postKeyEvent: @escaping @MainActor (CGKeyCode, CGEventFlags) -> Void,
        sleep: @escaping @MainActor (UInt64) async -> Void
    ) {
        self.textConverter = textConverter
        self.focused = focused
        self.focusedElementProvider = focusedElementProvider
        self.pasteboardRead = pasteboardRead
        self.pasteboardWrite = pasteboardWrite
        self.postKeyEvent = postKeyEvent
        self.sleep = sleep
    }

    enum Result: Sendable {
        case success(conversion: Conversion, method: Method)
        case failure(Reason)

        struct Conversion: Sendable {
            let sourceText: String
            let convertedText: String
            let sourceLanguage: LanguageID
            let targetLanguage: LanguageID
        }

        enum Method: Sendable {
            case accessibility
            case clipboard
        }

        enum Reason: Sendable {
            case noSelection
            case emptyText
            case tooLong
            case unsupportedApp
            case conversionFailed
        }
    }

    func convertSelection() async -> Result {
        switch await applyToSelection({ textConverter.convert($0) }) {
        case .transformed(let source, let result, let method):
            let language = detectLanguage(source)
            return .success(
                conversion: .init(
                    sourceText: source,
                    convertedText: result,
                    sourceLanguage: language,
                    targetLanguage: target(for: language)
                ),
                method: method
            )
        case .skipped(let reason):
            return .failure(reason)
        }
    }

    /// Cycles the selected text's letter casing (lower → UPPER → Title → lower).
    /// Returns `true` when a replacement was applied.
    @discardableResult
    func cycleSelectionCase() async -> Bool {
        if case .transformed = await applyToSelection({ SelectionCase.cycled($0) }) {
            return true
        }
        return false
    }

    private enum SelectionOutcome {
        case transformed(source: String, result: String, method: Result.Method)
        case skipped(Result.Reason)
    }

    /// Reads the current selection (Accessibility first, clipboard fallback),
    /// applies `transform`, and writes the result back. Shared by layout
    /// conversion and case cycling so the read/replace machinery lives once.
    private func applyToSelection(_ transform: (String) -> String?) async -> SelectionOutcome {
        if let outcome = applyViaAccessibility(transform) {
            return outcome
        }
        return await applyViaClipboard(transform)
    }

    private func applyViaAccessibility(_ transform: (String) -> String?) -> SelectionOutcome? {
        guard let element = focusedElementProvider() else { return nil }
        var selectedText: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )
        guard status == .success,
              let text = selectedText as? String,
              !text.isEmpty else { return nil }

        guard text.count <= textConverter.maxSelectionLength else {
            return .skipped(.tooLong)
        }
        guard let converted = transform(text), converted != text else {
            return .skipped(.conversionFailed)
        }

        let axStatus = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            converted as CFTypeRef
        )
        guard axStatus == .success else { return nil }

        return .transformed(source: text, result: converted, method: .accessibility)
    }

    private func applyViaClipboard(_ transform: (String) -> String?) async -> SelectionOutcome {
        let originalClipboard = pasteboardRead()

        postKeyEvent(8, [.maskCommand]) // Cmd+C
        await sleep(50_000_000)

        guard let text = pasteboardRead(), !text.isEmpty else {
            return .skipped(.noSelection)
        }
        guard text.count <= textConverter.maxSelectionLength else {
            return .skipped(.tooLong)
        }
        guard let converted = transform(text), converted != text else {
            return .skipped(.conversionFailed)
        }

        pasteboardWrite(converted)
        postKeyEvent(9, [.maskCommand]) // Cmd+V

        await sleep(50_000_000)
        if let originalClipboard {
            pasteboardWrite(originalClipboard)
        }

        return .transformed(source: text, result: converted, method: .clipboard)
    }

    private func detectLanguage(_ text: String) -> LanguageID {
        let cyrillicRange = "\u{0400}"..."\u{04FF}"
        return text.contains(where: { cyrillicRange.contains(String($0)) }) ? .ru : .en
    }

    private func target(for source: LanguageID) -> LanguageID {
        switch source {
        case .en: return .ru
        case .ru, .uk: return .en
        case .ro: return .en
        }
    }
}
