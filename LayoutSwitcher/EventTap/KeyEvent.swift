import CoreGraphics
import Foundation

/// Normalized keyboard/mouse event payload consumed by the typing pipeline.
struct KeyEvent: Sendable {
    /// Coarse event category used by classifier and hotkey routing.
    enum Kind: Equatable, Sendable {
        case keyDown
        case flagsChanged
        case leftMouseDown
        case rightMouseDown
        case other(CGEventType)
    }

    let kind: Kind
    let keyCode: CGKeyCode
    let flags: CGEventFlags
    let unicode: String
    let isAutoRepeat: Bool
    let sourcePID: pid_t
    let timestamp: UInt64

    /// Convenience initializer used in tests and fixtures.
    init(
        kind: Kind = .keyDown,
        keyCode: CGKeyCode,
        flags: CGEventFlags = [],
        unicode: String,
        isAutoRepeat: Bool = false,
        sourcePID: pid_t = 0,
        timestamp: UInt64 = 0
    ) {
        self.kind = kind
        self.keyCode = keyCode
        self.flags = flags
        self.unicode = unicode
        self.isAutoRepeat = isAutoRepeat
        self.sourcePID = sourcePID
        self.timestamp = timestamp
    }

    /// Converts native `CGEvent` into normalized event representation.
    init?(cgEvent: CGEvent) {
        let type = cgEvent.type
        switch type {
        case .keyDown: self.kind = .keyDown
        case .flagsChanged: self.kind = .flagsChanged
        case .leftMouseDown: self.kind = .leftMouseDown
        case .rightMouseDown: self.kind = .rightMouseDown
        default: self.kind = .other(type)
        }

        let kc = CGKeyCode(cgEvent.getIntegerValueField(.keyboardEventKeycode))
        self.keyCode = kc
        self.flags = cgEvent.flags
        self.isAutoRepeat = cgEvent.getIntegerValueField(.keyboardEventAutorepeat) != 0
        self.sourcePID = pid_t(cgEvent.getIntegerValueField(.eventTargetUnixProcessID))
        self.timestamp = cgEvent.timestamp

        if type == .keyDown || type == .keyUp {
            var length = 0
            var buffer = [UniChar](repeating: 0, count: 8)
            cgEvent.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &buffer)
            self.unicode = length > 0 ? String(utf16CodeUnits: buffer, count: length) : ""
        } else {
            self.unicode = ""
        }
    }
}
