import AppKit

/// Visual state shown in the menu-bar status icon. Snooze/presentation
/// counters are surfaced separately via the button title and do not affect
/// the icon glyph itself.
@MainActor
enum StatusBarIconState: Equatable {
    case secure
    case disabled
    case language(code: String)
    case fallback
}

/// Renders the menu-bar icon for a given state. Language variants overlay a
/// 2-letter code on top of an SF Symbol keyboard glyph; the result is a
/// template image so the menu bar adapts color in light/dark/secondary modes.
@MainActor
enum StatusBarIconRenderer {
    private static let canvas = NSSize(width: 22, height: 18)

    static func image(for state: StatusBarIconState) -> NSImage {
        switch state {
        case .secure:
            return symbolImage("lock.fill") ?? fallbackImage()
        case .disabled:
            return symbolImage("keyboard.chevron.compact.down") ?? fallbackImage()
        case .language(let code):
            return composedLanguageImage(code: code) ?? fallbackImage()
        case .fallback:
            return fallbackImage()
        }
    }

    private static func symbolImage(_ name: String) -> NSImage? {
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }
        img.isTemplate = true
        return img
    }

    private static func fallbackImage() -> NSImage {
        symbolImage("keyboard") ?? NSImage(size: canvas)
    }

    private static func composedLanguageImage(code: String) -> NSImage? {
        let label = StatusItemController.languageBadge(code)
        let baseName = ["RU", "UK"].contains(label) ? "keyboard.fill" : "keyboard"
        guard let base = NSImage(systemSymbolName: baseName, accessibilityDescription: nil) else {
            return nil
        }
        base.isTemplate = true

        let composed = NSImage(size: canvas, flipped: false) { rect in
            // Keyboard glyph occupies the upper ~70% of the canvas; the language
            // label sits underneath, centered, drawn in black so menu bar
            // template rendering can recolor the entire image uniformly.
            let glyphHeight = rect.height * 0.70
            let glyphRect = NSRect(
                x: 0,
                y: rect.height - glyphHeight,
                width: rect.width,
                height: glyphHeight
            )
            base.draw(in: glyphRect)

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 7, weight: .heavy),
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph,
                .kern: -0.2
            ]
            let str = NSAttributedString(string: label, attributes: attrs)
            let textRect = NSRect(
                x: 0,
                y: 0,
                width: rect.width,
                height: rect.height - glyphHeight
            )
            str.draw(in: textRect)
            return true
        }
        composed.isTemplate = true
        return composed
    }
}
