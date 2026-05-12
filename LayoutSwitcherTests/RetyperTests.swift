import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import LayoutSwitcher

@MainActor
struct RetyperTests {
    @Test func missingTargetLayoutAbortsBeforePostingEvents() async {
        var postedKeys: [CGKeyCode] = []
        var postedUnicode: [String] = []
        var selectedLayouts: [RetypeInputSource] = []

        let retyper = Retyper(
            mapping: RuEnQwertyMapping(),
            inputSources: InputSourceManager(),
            enabledLayoutsProvider: { [] },
            currentLayoutIDProvider: { "com.apple.keylayout.ABC" },
            refreshCurrentLayout: {},
            selectLayout: { layout in
                selectedLayouts.append(layout)
                return noErr
            },
            sleep: { _ in },
            postKeyEvent: { keyCode, _ in postedKeys.append(keyCode) },
            postUnicodeEvent: { postedUnicode.append($0) }
        )

        let succeeded = await retyper.retype(
            original: Self.wordChars([5, 4, 11, 2, 17, 45]),
            corrected: "привет",
            targetLanguage: .ru,
            separator: .space
        )

        #expect(!succeeded)
        #expect(selectedLayouts.isEmpty)
        #expect(postedKeys.isEmpty)
        #expect(postedUnicode.isEmpty)
    }

    @Test func unconfirmedLayoutSwitchAbortsBeforeBackspace() async {
        var postedKeys: [CGKeyCode] = []
        var selectedLayouts: [RetypeInputSource] = []

        let retyper = Retyper(
            mapping: RuEnQwertyMapping(),
            inputSources: InputSourceManager(),
            enabledLayoutsProvider: {
                [RetypeInputSource(id: "com.apple.keylayout.RussianWin", primaryLanguage: "ru")]
            },
            currentLayoutIDProvider: { "com.apple.keylayout.ABC" },
            refreshCurrentLayout: {},
            selectLayout: { layout in
                selectedLayouts.append(layout)
                return noErr
            },
            sleep: { _ in },
            postKeyEvent: { keyCode, _ in postedKeys.append(keyCode) },
            postUnicodeEvent: { _ in }
        )

        let succeeded = await retyper.retype(
            original: Self.wordChars([5, 4, 11, 2, 17, 45]),
            corrected: "привет",
            targetLanguage: .ru,
            separator: .space
        )

        #expect(!succeeded)
        #expect(selectedLayouts == [RetypeInputSource(id: "com.apple.keylayout.RussianWin", primaryLanguage: "ru")])
        #expect(postedKeys.isEmpty)
    }

    @Test func romanianDiacriticsAreEncodedWithTargetLayoutData() async {
        var posted: [(CGKeyCode, CGEventFlags)] = []
        var postedUnicode: [String] = []

        let retyper = Retyper(
            mapping: RuEnQwertyMapping(),
            inputSources: InputSourceManager(),
            currentLayoutIDProvider: { "com.apple.keylayout.Romanian-Standard" },
            refreshCurrentLayout: {},
            sleep: { _ in },
            postKeyEvent: { keyCode, flags in posted.append((keyCode, flags)) },
            postUnicodeEvent: { postedUnicode.append($0) }
        )

        let succeeded = await retyper.retype(
            original: Self.wordChars([11, 32, 45, 0]),
            corrected: "bună",
            targetLanguage: .ro,
            separator: .space
        )

        #expect(succeeded)
        #expect(postedUnicode.isEmpty)
        #expect(posted.map(\.0) == [51, 51, 51, 51, 51, 11, 32, 45, 33, 49])
        #expect(posted.map(\.1) == Array(repeating: CGEventFlags(), count: posted.count))
    }

    @Test func romanianDiacriticsRequireRomanianLayout() async {
        var postedKeys: [CGKeyCode] = []
        var selectedLayouts: [RetypeInputSource] = []

        let retyper = Retyper(
            mapping: RuEnQwertyMapping(),
            inputSources: InputSourceManager(),
            enabledLayoutsProvider: {
                [RetypeInputSource(id: "com.apple.keylayout.ABC", primaryLanguage: "en")]
            },
            currentLayoutIDProvider: { "com.apple.keylayout.ABC" },
            refreshCurrentLayout: {},
            selectLayout: { layout in
                selectedLayouts.append(layout)
                return noErr
            },
            sleep: { _ in },
            postKeyEvent: { keyCode, _ in postedKeys.append(keyCode) },
            postUnicodeEvent: { _ in }
        )

        let succeeded = await retyper.retype(
            original: Self.wordChars([11, 32, 45, 0]),
            corrected: "bună",
            targetLanguage: .ro,
            separator: .space
        )

        #expect(!succeeded)
        #expect(selectedLayouts.isEmpty)
        #expect(postedKeys.isEmpty)
    }

    @Test func romanianDiacriticsReturnMissingRomanianLayoutReason() async {
        let retyper = Retyper(
            mapping: RuEnQwertyMapping(),
            inputSources: InputSourceManager(),
            enabledLayoutsProvider: {
                [RetypeInputSource(id: "com.apple.keylayout.ABC", primaryLanguage: "en")]
            },
            currentLayoutIDProvider: { "com.apple.keylayout.ABC" },
            refreshCurrentLayout: {},
            sleep: { _ in },
            postKeyEvent: { _, _ in },
            postUnicodeEvent: { _ in }
        )

        let result = await retyper.retypeResult(
            original: Self.wordChars([11, 32, 45, 0]),
            corrected: "bună",
            targetLanguage: .ro,
            separator: .space
        )

        #expect(result == .failure(.missingRomanianLayout))
    }

    @Test func sequenceRetypeEncodesInternalSpacesAsKeyEvents() async {
        var posted: [(CGKeyCode, CGEventFlags)] = []
        var postedUnicode: [String] = []

        let retyper = Retyper(
            mapping: RuEnQwertyMapping(),
            inputSources: InputSourceManager(),
            currentLayoutIDProvider: { "com.apple.keylayout.RussianWin" },
            refreshCurrentLayout: {},
            sleep: { _ in },
            postKeyEvent: { keyCode, flags in posted.append((keyCode, flags)) },
            postUnicodeEvent: { postedUnicode.append($0) }
        )

        let result = await retyper.retypeSequenceResult(
            original: Self.wordChars([5, 4, 11, 2, 17, 45, 49, 9, 11, 4]),
            corrected: "привет мир",
            targetLanguage: .ru,
            finalSeparator: .space
        )

        #expect(result == .success)
        #expect(postedUnicode.isEmpty)
        #expect(Array(posted.map(\.0).prefix(11)) == Array(repeating: 51, count: 11))
        #expect(Array(posted.map(\.0).dropFirst(11)) == [5, 4, 11, 2, 17, 45, 49, 9, 11, 4, 49])
    }

    @Test func sequenceRetypeRestoresFinalPunctuationAsUnicode() async {
        var postedKeys: [CGKeyCode] = []
        var postedUnicode: [String] = []

        let retyper = Retyper(
            mapping: RuEnQwertyMapping(),
            inputSources: InputSourceManager(),
            currentLayoutIDProvider: { "com.apple.keylayout.RussianWin" },
            refreshCurrentLayout: {},
            sleep: { _ in },
            postKeyEvent: { keyCode, _ in postedKeys.append(keyCode) },
            postUnicodeEvent: { postedUnicode.append($0) }
        )

        let result = await retyper.retypeSequenceResult(
            original: Self.wordChars([5, 4, 11, 2, 17, 45, 49, 9, 11, 4]),
            corrected: "привет мир",
            targetLanguage: .ru,
            finalSeparator: .punctuation("!")
        )

        #expect(result == .success)
        #expect(Array(postedKeys.prefix(11)) == Array(repeating: 51, count: 11))
        #expect(postedUnicode == ["!"])
    }

    private static func wordChars(_ keyCodes: [CGKeyCode]) -> [WordChar] {
        keyCodes.map {
            WordChar(keyCode: $0, unicode: "", flags: [], timestamp: 0)
        }
    }
}
