import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct KeyCodeEncoderTests {
    @Test func encodesLowercaseAFromInjectedTranslator() {
        let encoded = KeyCodeEncoder.encode(
            "a",
            layoutData: Self.fakeLayoutData,
            keyboardType: 0,
            keyTranslator: Self.translator(outputs: [
                .init(keyCode: 0, modifiers: 0, output: "a")
            ])
        )

        #expect(encoded != nil)
        #expect(encoded?.keyCode == 0)
        #expect(encoded?.flags == [])
    }

    @Test func encodesUppercaseAWithShiftFromInjectedTranslator() {
        let encoded = KeyCodeEncoder.encode(
            "A",
            layoutData: Self.fakeLayoutData,
            keyboardType: 0,
            keyTranslator: Self.translator(outputs: [
                .init(keyCode: 0, modifiers: Self.shiftModifier, output: "A")
            ])
        )

        #expect(encoded != nil)
        #expect(encoded?.keyCode == 0)
        #expect(encoded?.flags.contains(.maskShift) == true)
    }

    @Test func encodesAlternateModifiedCharacter() {
        let encoded = KeyCodeEncoder.encode(
            "ø",
            layoutData: Self.fakeLayoutData,
            keyboardType: 0,
            keyTranslator: Self.translator(outputs: [
                .init(keyCode: 31, modifiers: Self.optionModifier, output: "ø")
            ])
        )

        #expect(encoded?.keyCode == 31)
        #expect(encoded?.flags.contains(.maskAlternate) == true)
    }

    @Test func returnsNilForUnsupportedCharacter() {
        let encoded = KeyCodeEncoder.encode(
            "\u{1F600}",
            layoutData: Self.fakeLayoutData,
            keyboardType: 0,
            keyTranslator: Self.translator(outputs: [])
        )

        #expect(encoded == nil)
    }

    @Test func ignoresFailedTranslatorStatus() {
        let encoded = KeyCodeEncoder.encode(
            "a",
            layoutData: Self.fakeLayoutData,
            keyboardType: 0,
            keyTranslator: { _, _, _, _, _, _, _, _, actualStringLength, _ in
                actualStringLength.pointee = 0
                return OSStatus(paramErr)
            }
        )

        #expect(encoded == nil)
    }

    private static let fakeLayoutData = Data([0])
    private static let shiftModifier = UInt32(shiftKey >> 8)
    private static let optionModifier = UInt32(optionKey >> 8)

    private struct Translation {
        let keyCode: UInt16
        let modifiers: UInt32
        let output: String
    }

    private static func translator(outputs: [Translation]) -> KeyCodeEncoder.KeyTranslator {
        { _, keyCode, _, modifiers, _, _, _, maxStringLength, actualStringLength, unicodeString in
            guard let output = outputs.first(where: { $0.keyCode == keyCode && $0.modifiers == modifiers }) else {
                actualStringLength.pointee = 0
                return OSStatus(noErr)
            }

            let utf16 = Array(output.output.utf16)
            guard utf16.count <= maxStringLength else {
                actualStringLength.pointee = 0
                return OSStatus(paramErr)
            }

            for (index, unit) in utf16.enumerated() {
                unicodeString[index] = unit
            }
            actualStringLength.pointee = utf16.count
            return OSStatus(noErr)
        }
    }
}
