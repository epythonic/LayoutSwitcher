import CoreGraphics
import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct SmartPasteTests {
    private func makePaste(
        clipboard: String?,
        inputSources: FakeInputSources = FakeInputSources.defaultRuEn(),
        capture: PasteCapture
    ) -> SmartPaste {
        capture.clipboard = clipboard
        return SmartPaste(
            inputSources: inputSources,
            pasteboardRead: { capture.clipboard },
            postKeyEvent: { keyCode, flags in
                capture.postedKeys.append((keyCode, flags))
            },
            sleep: { duration in
                capture.sleepDurations.append(duration)
            }
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
        let isPasted: Bool
        let pastedLanguage: LanguageID?
        if case .pasted(let lang, _) = result {
            isPasted = true
            pastedLanguage = lang
        } else {
            isPasted = false
            pastedLanguage = nil
        }
        #expect(isPasted)
        #expect(pastedLanguage == .ru)
        #expect(capture.postedKeys.contains(where: { $0.keyCode == 9 && $0.flags.contains(.maskCommand) }))
    }

    @Test func englishClipboardDetectedAsEnglish() async {
        let capture = PasteCapture()
        let paste = makePaste(clipboard: "hello world", capture: capture)
        let result = await paste.paste()
        let isPasted: Bool
        let pastedLanguage: LanguageID?
        if case .pasted(let lang, _) = result {
            isPasted = true
            pastedLanguage = lang
        } else {
            isPasted = false
            pastedLanguage = nil
        }
        #expect(isPasted)
        #expect(pastedLanguage == .en)
    }

    @Test func englishClipboardAlreadyCurrentDoesNotSwitchLayout() async {
        let capture = PasteCapture()
        let inputSources = FakeInputSources.defaultRuEn(currentID: "com.apple.keylayout.ABC")
        let paste = makePaste(clipboard: "hello", inputSources: inputSources, capture: capture)
        let result = await paste.paste()

        #expect(result == .pasted(language: .en, layoutSwitched: false))
        #expect(inputSources.selectedHistory.isEmpty)
        #expect(inputSources.refreshCount == 0)
        #expect(capture.sleepDurations == [20_000_000])
        #expect(capture.postedKeys.count == 1)
        #expect(capture.postedKeys.first?.keyCode == 9)
        #expect(capture.postedKeys.first?.flags.contains(.maskCommand) == true)
    }

    @Test func russianClipboardSwitchesLayoutBeforePostingPaste() async {
        let capture = PasteCapture()
        let inputSources = FakeInputSources.defaultRuEn(currentID: "com.apple.keylayout.ABC")
        let paste = makePaste(clipboard: "привет", inputSources: inputSources, capture: capture)
        let result = await paste.paste()

        #expect(result == .pasted(language: .ru, layoutSwitched: true))
        #expect(inputSources.selectedHistory == ["com.apple.keylayout.RussianWin"])
        #expect(inputSources.refreshCount == 1)
        #expect(capture.sleepDurations == [40_000_000, 20_000_000])
        #expect(capture.postedKeys.count == 1)
        #expect(capture.postedKeys.first?.keyCode == 9)
        #expect(capture.postedKeys.first?.flags.contains(.maskCommand) == true)
    }

    @Test func ukrainianGlyphSelectsUkrainianTarget() async {
        let capture = PasteCapture()
        let paste = makePaste(clipboard: "привіт", capture: capture)
        let result = await paste.paste()
        let isPasted: Bool
        let pastedLanguage: LanguageID?
        if case .pasted(let lang, _) = result {
            isPasted = true
            pastedLanguage = lang
        } else {
            isPasted = false
            pastedLanguage = nil
        }
        #expect(isPasted)
        #expect(pastedLanguage == .uk)
    }

    @Test func romanianDiacriticSelectsRomanianTarget() async {
        let capture = PasteCapture()
        let paste = makePaste(clipboard: "bună", capture: capture)
        let result = await paste.paste()
        let isPasted: Bool
        let pastedLanguage: LanguageID?
        if case .pasted(let lang, _) = result {
            isPasted = true
            pastedLanguage = lang
        } else {
            isPasted = false
            pastedLanguage = nil
        }
        #expect(isPasted)
        #expect(pastedLanguage == .ro)
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
    var sleepDurations: [UInt64] = []
}
