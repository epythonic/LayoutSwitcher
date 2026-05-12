import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import os

/// Performs manual "convert selected text" through Accessibility first, then clipboard.
@MainActor
final class SelectionConverter {
    private static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "SelectionConverter")

    private let textConverter: SelectionTextConverter
    private let focused: FocusedAppObserving
    private let focusedElementProvider: () -> AXUIElement?
    private let pasteboardRead: () -> String?
    private let pasteboardWrite: (String) -> Void
    private let postKeyEvent: (CGKeyCode, CGEventFlags) -> Void
    private let sleep: (UInt64) async -> Void

    init(mapping: any KeyboardMapping, focused: FocusedAppObserving) {
        self.textConverter = SelectionTextConverter(mapping: mapping)
        self.focused = focused
        self.focusedElementProvider = {
            let systemWide = AXUIElementCreateSystemWide()
            var focusedElement: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(
                systemWide,
                kAXFocusedUIElementAttribute as CFString,
                &focusedElement
            )
            guard status == .success,
                  let element = focusedElement,
                  CFGetTypeID(element) == AXUIElementGetTypeID() else {
                return nil
            }
            return unsafeBitCast(element, to: AXUIElement.self)
        }
        self.pasteboardRead = {
            NSPasteboard.general.string(forType: .string)
        }
        self.pasteboardWrite = { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        self.postKeyEvent = { keyCode, flags in
            guard let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
                  let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
                return
            }
            eventDown.flags = flags
            eventUp.flags = flags
            SyntheticEventFilter.tag(eventDown)
            SyntheticEventFilter.tag(eventUp)
            eventDown.post(tap: .cghidEventTap)
            eventUp.post(tap: .cghidEventTap)
        }
        self.sleep = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    }

    init(
        textConverter: SelectionTextConverter,
        focused: FocusedAppObserving,
        focusedElementProvider: @escaping () -> AXUIElement?,
        pasteboardRead: @escaping () -> String?,
        pasteboardWrite: @escaping (String) -> Void,
        postKeyEvent: @escaping (CGKeyCode, CGEventFlags) -> Void,
        sleep: @escaping (UInt64) async -> Void
    ) {
        self.textConverter = textConverter
        self.focused = focused
        self.focusedElementProvider = focusedElementProvider
        self.pasteboardRead = pasteboardRead
        self.pasteboardWrite = pasteboardWrite
        self.postKeyEvent = postKeyEvent
        self.sleep = sleep
    }

    enum Result {
        case success(conversion: Conversion, method: Method)
        case failure(Reason)

        struct Conversion {
            let sourceText: String
            let convertedText: String
            let sourceLanguage: LanguageID
            let targetLanguage: LanguageID
        }

        enum Method {
            case accessibility
            case clipboard
        }

        enum Reason {
            case noSelection
            case emptyText
            case tooLong
            case unsupportedApp
            case conversionFailed
        }
    }

    func convertSelection() async -> Result {
        if let accessibilityResult = tryAccessibility() {
            return accessibilityResult
        }
        return await tryClipboard()
    }

    private func tryAccessibility() -> Result? {
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
            return .failure(.tooLong)
        }

        let converted = textConverter.convert(text)
        guard converted != text else { return .failure(.conversionFailed) }

        let axStatus = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            converted as CFTypeRef
        )
        guard axStatus == .success else { return nil }

        return .success(
            conversion: .init(
                sourceText: text,
                convertedText: converted,
                sourceLanguage: detectLanguage(text),
                targetLanguage: target(for: detectLanguage(text))
            ),
            method: .accessibility
        )
    }

    private func tryClipboard() async -> Result {
        let originalClipboard = pasteboardRead()

        postKeyEvent(8, [.maskCommand]) // Cmd+C
        await sleep(50_000_000)

        guard let text = pasteboardRead(), !text.isEmpty else {
            return .failure(.noSelection)
        }

        guard text.count <= textConverter.maxSelectionLength else {
            return .failure(.tooLong)
        }

        let converted = textConverter.convert(text)
        guard converted != text else { return .failure(.conversionFailed) }

        pasteboardWrite(converted)
        postKeyEvent(9, [.maskCommand]) // Cmd+V

        await sleep(50_000_000)
        if let originalClipboard {
            pasteboardWrite(originalClipboard)
        }

        return .success(
            conversion: .init(
                sourceText: text,
                convertedText: converted,
                sourceLanguage: detectLanguage(text),
                targetLanguage: target(for: detectLanguage(text))
            ),
            method: .clipboard
        )
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
