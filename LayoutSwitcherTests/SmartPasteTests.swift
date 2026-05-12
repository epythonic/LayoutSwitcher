import CoreGraphics
import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct SmartPasteTests {
    private func makePaste(clipboard: String?, capture: PasteCapture) -> SmartPaste {
        let inputSources = FakeInputSources.defaultRuEn()
        capture.clipboard = clipboard
        return SmartPaste(
            inputSources: inputSources,
            pasteboardRead: { capture.clipboard },
            postKeyEvent: { keyCode, flags in
                capture.postedKeys.append((keyCode, flags))
            },
            sleep: { _ in }
        )
    }

    @Test func emptyClipboardReturnsClipboardEmpty() async {
        let capture = PasteCapture()
        let paste = makePaste(clipboard: nil, capture: capture)
        let result = await paste.paste()
        #expect(result == .clipboardEmpty)
        #expect(capture.postedKeys.isEmpty)
    }

    @Test func russianClipboardDetectedAsRussianAndPasted() async {
        let capture = PasteCapture()
        let paste = makePaste(clipboard: "привет", capture: capture)
        let result = await paste.paste()
        if case .pasted(let lang, _) = result {
            #expect(lang == .ru)
        } else {
            Issue.record("expected .pasted, got \(result)")
        }
        #expect(capture.postedKeys.contains(where: { $0.keyCode == 9 && $0.flags.contains(.maskCommand) }))
    }

    @Test func englishClipboardDetectedAsEnglish() async {
        let capture = PasteCapture()
        let paste = makePaste(clipboard: "hello world", capture: capture)
        let result = await paste.paste()
        if case .pasted(let lang, _) = result {
            #expect(lang == .en)
        } else {
            Issue.record("expected .pasted, got \(result)")
        }
    }

    @Test func ukrainianGlyphSelectsUkrainianTarget() async {
        let capture = PasteCapture()
        let paste = makePaste(clipboard: "привіт", capture: capture)
        let result = await paste.paste()
        if case .pasted(let lang, _) = result {
            #expect(lang == .uk)
        } else {
            Issue.record("expected .pasted, got \(result)")
        }
    }

    @Test func romanianDiacriticSelectsRomanianTarget() async {
        let capture = PasteCapture()
        let paste = makePaste(clipboard: "bună", capture: capture)
        let result = await paste.paste()
        if case .pasted(let lang, _) = result {
            #expect(lang == .ro)
        } else {
            Issue.record("expected .pasted, got \(result)")
        }
    }

    @Test func longClipboardReturnsTooLong() async {
        let capture = PasteCapture()
        let huge = String(repeating: "x", count: SelectionTextConverter.absoluteMaxSelectionLength + 1)
        let paste = makePaste(clipboard: huge, capture: capture)
        let result = await paste.paste()
        #expect(result == .tooLong)
        #expect(capture.postedKeys.isEmpty)
    }
}

@MainActor
private final class PasteCapture {
    var clipboard: String?
    var postedKeys: [(keyCode: CGKeyCode, flags: CGEventFlags)] = []
}
