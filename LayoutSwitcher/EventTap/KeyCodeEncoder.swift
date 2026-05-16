import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Key emission tuple representing keycode and modifier flags.
struct EncodedKey: Equatable, Sendable {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

/// Utility that resolves a Unicode character into keycode+modifier pair for a layout.
enum KeyCodeEncoder {
    typealias KeyTranslator = @MainActor (
        _ keyboardLayout: UnsafeRawPointer,
        _ keyCode: UInt16,
        _ action: UInt16,
        _ modifiers: UInt32,
        _ keyboardType: UInt32,
        _ options: UInt32,
        _ deadKeyState: UnsafeMutablePointer<UInt32>,
        _ maxStringLength: Int,
        _ actualStringLength: UnsafeMutablePointer<Int>,
        _ unicodeString: UnsafeMutablePointer<UniChar>
    ) -> OSStatus

    /// Brute-force searches keycode/modifier combinations via `UCKeyTranslate`.
    static func encode(
        _ character: Character,
        layoutData: Data,
        keyboardType: UInt32 = UInt32(LMGetKbdType()),
        keyTranslator: KeyTranslator = Self.translateKey
    ) -> EncodedKey? {
        let wanted = String(character)
        let modifierStates: [(carbon: UInt32, flags: CGEventFlags)] = [
            (0, []),
            (UInt32(shiftKey >> 8), [.maskShift]),
            (UInt32(optionKey >> 8), [.maskAlternate]),
            (UInt32((shiftKey | optionKey) >> 8), [.maskShift, .maskAlternate])
        ]

        return layoutData.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return nil }

            for keyCode in CGKeyCode(0)..<CGKeyCode(128) {
                for state in modifierStates {
                    var deadKeyState: UInt32 = 0
                    var length = 0
                    var chars = [UniChar](repeating: 0, count: 8)
                    let status = keyTranslator(
                        base,
                        UInt16(keyCode),
                        UInt16(kUCKeyActionDown),
                        state.carbon,
                        keyboardType,
                        UInt32(kUCKeyTranslateNoDeadKeysBit),
                        &deadKeyState,
                        chars.count,
                        &length,
                        &chars
                    )
                    guard status == noErr, length > 0 else { continue }
                    let produced = String(utf16CodeUnits: chars, count: length)
                    if produced == wanted {
                        return EncodedKey(keyCode: keyCode, flags: state.flags)
                    }
                }
            }
            return nil
        }
    }

    private static func translateKey(
        keyboardLayout: UnsafeRawPointer,
        keyCode: UInt16,
        action: UInt16,
        modifiers: UInt32,
        keyboardType: UInt32,
        options: UInt32,
        deadKeyState: UnsafeMutablePointer<UInt32>,
        maxStringLength: Int,
        actualStringLength: UnsafeMutablePointer<Int>,
        unicodeString: UnsafeMutablePointer<UniChar>
    ) -> OSStatus {
        UCKeyTranslate(
            keyboardLayout.assumingMemoryBound(to: UCKeyboardLayout.self),
            keyCode,
            action,
            modifiers,
            keyboardType,
            options,
            deadKeyState,
            maxStringLength,
            actualStringLength,
            unicodeString
        )
    }
}
