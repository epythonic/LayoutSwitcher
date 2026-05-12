import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Key emission tuple representing keycode and modifier flags.
struct EncodedKey: Equatable {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

/// Utility that resolves a Unicode character into keycode+modifier pair for a layout.
enum KeyCodeEncoder {
    /// Brute-force searches keycode/modifier combinations via `UCKeyTranslate`.
    static func encode(_ character: Character, layoutData: Data) -> EncodedKey? {
        let wanted = String(character)
        let keyboardType = UInt32(LMGetKbdType())
        let modifierStates: [(carbon: UInt32, flags: CGEventFlags)] = [
            (0, []),
            (UInt32(shiftKey >> 8), [.maskShift]),
            (UInt32(optionKey >> 8), [.maskAlternate]),
            (UInt32((shiftKey | optionKey) >> 8), [.maskShift, .maskAlternate])
        ]

        return layoutData.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return nil }
            let keyboardLayout = base.assumingMemoryBound(to: UCKeyboardLayout.self)

            for keyCode in CGKeyCode(0)..<CGKeyCode(128) {
                for state in modifierStates {
                    var deadKeyState: UInt32 = 0
                    var length = 0
                    var chars = [UniChar](repeating: 0, count: 8)
                    let status = UCKeyTranslate(
                        keyboardLayout,
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
}
