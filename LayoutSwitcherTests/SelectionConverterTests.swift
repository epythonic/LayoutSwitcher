import CoreGraphics
import Testing
@testable import LayoutSwitcher

@MainActor
struct SelectionConverterTests {
    @Test func clipboardFallbackConvertsPastesAndRestoresOriginalClipboard() async {
        let capture = ClipboardCapture(reads: ["original clipboard", "ghbdtn"])
        let converter = makeConverter(capture: capture)

        let result = await converter.convertSelection()

        let isSuccess: Bool
        let isClipboardMethod: Bool
        if case .success(let conversion, let method) = result {
            isSuccess = true
            if case .clipboard = method {
                isClipboardMethod = true
            } else {
                isClipboardMethod = false
            }
            #expect(conversion.sourceText == "ghbdtn")
            #expect(conversion.convertedText == "привет")
            #expect(conversion.sourceLanguage == .en)
            #expect(conversion.targetLanguage == .ru)
        } else {
            isSuccess = false
            isClipboardMethod = false
        }
        #expect(isSuccess)
        #expect(isClipboardMethod)
        #expect(capture.postedKeys.count == 2)
        #expect(capture.postedKeys.first?.keyCode == 8)
        #expect(capture.postedKeys.first?.flags.contains(.maskCommand) == true)
        #expect(capture.postedKeys.last?.keyCode == 9)
        #expect(capture.postedKeys.last?.flags.contains(.maskCommand) == true)
        #expect(capture.writes == ["привет", "original clipboard"])
        #expect(capture.sleepDurations == [50_000_000, 50_000_000])
    }

    @Test func clipboardFallbackReturnsNoSelectionWhenCopyProducesEmptyText() async {
        let capture = ClipboardCapture(reads: ["original clipboard", ""])
        let converter = makeConverter(capture: capture)

        let result = await converter.convertSelection()

        let isNoSelectionFailure: Bool
        if case .failure(let reason) = result, case .noSelection = reason {
            isNoSelectionFailure = true
        } else {
            isNoSelectionFailure = false
        }
        #expect(isNoSelectionFailure)
        #expect(capture.postedKeys.count == 1)
        #expect(capture.postedKeys.first?.keyCode == 8)
        #expect(capture.writes.isEmpty)
        #expect(capture.sleepDurations == [50_000_000])
    }

    @Test func clipboardFallbackRejectsTooLongSelectionBeforePaste() async {
        let hugeSelection = String(
            repeating: "x",
            count: SelectionTextConverter.absoluteMaxSelectionLength + 1
        )
        let capture = ClipboardCapture(reads: ["original clipboard", hugeSelection])
        let converter = makeConverter(capture: capture)

        let result = await converter.convertSelection()

        let isTooLongFailure: Bool
        if case .failure(let reason) = result, case .tooLong = reason {
            isTooLongFailure = true
        } else {
            isTooLongFailure = false
        }
        #expect(isTooLongFailure)
        #expect(capture.postedKeys.count == 1)
        #expect(capture.postedKeys.first?.keyCode == 8)
        #expect(capture.writes.isEmpty)
        #expect(capture.sleepDurations == [50_000_000])
    }

    @Test func clipboardFallbackDoesNotPasteWhenConversionDoesNotChangeText() async {
        let capture = ClipboardCapture(reads: ["original clipboard", "12345"])
        let converter = makeConverter(capture: capture)

        let result = await converter.convertSelection()

        let isConversionFailed: Bool
        if case .failure(let reason) = result, case .conversionFailed = reason {
            isConversionFailed = true
        } else {
            isConversionFailed = false
        }
        #expect(isConversionFailed)
        #expect(capture.postedKeys.count == 1)
        #expect(capture.postedKeys.first?.keyCode == 8)
        #expect(capture.writes.isEmpty)
        #expect(capture.sleepDurations == [50_000_000])
    }

    @Test func clipboardFallbackSkipsRestoreWhenOriginalClipboardIsNil() async {
        let capture = ClipboardCapture(reads: [nil, "ghbdtn"])
        let converter = makeConverter(capture: capture)

        let result = await converter.convertSelection()

        let isSuccess: Bool
        let isClipboardMethod: Bool
        if case .success(let conversion, let method) = result {
            isSuccess = true
            if case .clipboard = method {
                isClipboardMethod = true
            } else {
                isClipboardMethod = false
            }
            #expect(conversion.convertedText == "привет")
        } else {
            isSuccess = false
            isClipboardMethod = false
        }
        #expect(isSuccess)
        #expect(isClipboardMethod)
        #expect(capture.postedKeys.count == 2)
        #expect(capture.postedKeys.first?.keyCode == 8)
        #expect(capture.postedKeys.last?.keyCode == 9)
        #expect(capture.writes == ["привет"])
        #expect(capture.sleepDurations == [50_000_000, 50_000_000])
    }

    private func makeConverter(capture: ClipboardCapture) -> SelectionConverter {
        SelectionConverter(
            textConverter: SelectionTextConverter(mapping: RuEnQwertyMapping()),
            focused: FakeFocusedApp(),
            focusedElementProvider: { nil },
            pasteboardRead: { capture.read() },
            pasteboardWrite: { capture.writes.append($0) },
            postKeyEvent: { keyCode, flags in
                capture.postedKeys.append((keyCode, flags))
            },
            sleep: { duration in
                capture.sleepDurations.append(duration)
            }
        )
    }
}

@MainActor
private final class ClipboardCapture {
    private var reads: [String?]
    var writes: [String] = []
    var postedKeys: [(keyCode: CGKeyCode, flags: CGEventFlags)] = []
    var sleepDurations: [UInt64] = []

    init(reads: [String?]) {
        self.reads = reads
    }

    func read() -> String? {
        guard !reads.isEmpty else { return nil }
        return reads.removeFirst()
    }
}

@MainActor
private final class FakeFocusedApp: FocusedAppObserving {
    var bundleID: String?
    var localizedName: String?
    var isSecureField = false
    var onChange: (@MainActor () -> Void)?

    func refreshSecureFieldState() {}
}
