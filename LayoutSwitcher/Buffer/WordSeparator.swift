import CoreGraphics

/// Token delimiters that finalize buffered word capture.
enum WordSeparator: Equatable, Sendable {
    case space
    case enter
    case tab
    case punctuation(Character)
}

/// Reasons why current buffered token was reset.
enum WordResetReason: Sendable {
    case appChanged
    case mouseClick
    case navigation
    case escape
    case modifierShortcut
    case manual
}

/// High-level key categories used by pipeline state machine.
enum KeyCodeKind: Equatable, Sendable {
    case letter
    case separator(WordSeparator)
    case backspace
    case navigation
    case escape
    case modifierOnly
    case digit
    case other
}

/// Layout-aware tokenizer that decides whether a raw key event belongs to the
/// current word or terminates it, based on the active keyboard mapping table.
struct TokenBoundaryPolicy {
    let mapping: KeyboardMapping

    /// Classifies the event using base Unicode rules, then overrides any
    /// punctuation-shaped keycodes that are letters in another supported layout.
    func classify(_ event: KeyEvent) -> KeyCodeKind {
        let base = KeyClassifier.classify(event)

        // If the base classifier sees punctuation, but this keycode produces
        // letters in another supported layout, treat it as a word character.
        if case .separator(.punctuation) = base,
           mapping.ambiguousWordInternalKeyCodes.contains(event.keyCode) {
            return .letter
        }

        return base
    }
}

/// Converts raw key events into semantic categories for buffering logic.
enum KeyClassifier {
    /// Classifies one normalized event into pipeline-oriented key kind.
    static func classify(_ event: KeyEvent) -> KeyCodeKind {
        guard case .keyDown = event.kind else { return .other }

        switch event.keyCode {
        case 36, 76: return .separator(.enter)
        case 48: return .separator(.tab)
        case 49: return .separator(.space)
        case 51: return .backspace
        case 53: return .escape
        case 55, 56, 57, 58, 59, 60, 61, 62, 63: return .modifierOnly
        case 115, 116, 117, 119, 121, 123, 124, 125, 126: return .navigation
        default:
            break
        }

        if let scalar = event.unicode.unicodeScalars.first {
            let ch = Character(scalar)
            if ch.isLetter {
                return .letter
            }
            if ch.isNumber {
                return .digit
            }
            if ch.isPunctuation || ch.isSymbol {
                return .separator(.punctuation(ch))
            }
            if ch.isWhitespace {
                return .separator(.space)
            }
        }
        return .other
    }
}
