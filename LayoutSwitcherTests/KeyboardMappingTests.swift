import Testing
import CoreGraphics
@testable import LayoutSwitcher

@MainActor
struct KeyboardMappingTests {
    let mapping = RuEnQwertyMapping()

    private func chars(_ keyCodes: [CGKeyCode], shift: Bool = false) -> [WordChar] {
        let flags: CGEventFlags = shift ? .maskShift : []
        return keyCodes.map { WordChar(keyCode: $0, unicode: "", flags: flags, timestamp: 0) }
    }

    @Test func ghbdtnTransliteratesToПривет() {
        // g h b d t n  -> keyCodes 5, 4, 11, 2, 17, 45
        let buffer = chars([5, 4, 11, 2, 17, 45])
        #expect(mapping.transliterate(buffer, to: .ru) == "привет")
        #expect(mapping.transliterate(buffer, to: .en) == "ghbdtn")
    }

    @Test func ghbdsnTransliteratesToПривіт() {
        let buffer = chars([5, 4, 11, 2, 1, 45])
        #expect(mapping.transliterate(buffer, to: .uk) == "привіт")
        #expect(mapping.transliterate(buffer, to: .en) == "ghbdsn")
    }

    @Test func рудддщTransliteratesToHello() {
        // р у д д щ  -> keyCodes 4, 14, 37, 37, 31 (matches HELLO in EN, but used as wrong-layout source)
        // hello -> h e l l o -> keyCodes 4, 14, 37, 37, 31
        let buffer = chars([4, 14, 37, 37, 31])
        #expect(mapping.transliterate(buffer, to: .en) == "hello")
        #expect(mapping.transliterate(buffer, to: .ru) == "руддщ")
    }

    @Test func shiftProducesUppercase() {
        let buffer = chars([4, 14, 37, 37, 31], shift: true)
        #expect(mapping.transliterate(buffer, to: .en) == "HELLO")
        #expect(mapping.transliterate(buffer, to: .ru) == "РУДДЩ")
    }

    @Test func roundTripPreservesText() {
        // Take an EN word, render in EN and RU, then re-render the RU keyCodes back to EN.
        let buffer = chars([5, 4, 11, 2, 17, 45])
        let en = mapping.transliterate(buffer, to: .en)
        let ru = mapping.transliterate(buffer, to: .ru)
        #expect(en == "ghbdtn")
        #expect(ru == "привет")
    }

    @Test func unmappedKeyIsSkipped() {
        // Use an unlikely keyCode (e.g. 200) — it should be ignored.
        let buffer = [
            WordChar(keyCode: 5,   unicode: "", flags: [], timestamp: 0),
            WordChar(keyCode: 200, unicode: "", flags: [], timestamp: 0),
            WordChar(keyCode: 4,   unicode: "", flags: [], timestamp: 0)
        ]
        #expect(mapping.transliterate(buffer, to: .ru) == "пр")
    }
}
