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
/// 2-letter code inside a compact switch glyph; the result is a template image
/// so the menu bar adapts color in light/dark/secondary modes.
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
            return switchImage(label: StatusItemController.languageBadge(code)) ?? fallbackImage()
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
        switchImage(label: nil) ?? symbolImage("keyboard") ?? NSImage(size: canvas)
    }

    private static func switchImage(label: String?) -> NSImage? {
        guard let base = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil) else {
            return nil
        }
        base.isTemplate = true

        let composed = NSImage(size: canvas, flipped: false) { rect in
            let glyphRect = NSRect(
                x: 1,
                y: 1,
                width: rect.width - 2,
                height: rect.height - 2
            )
            base.draw(in: glyphRect)

            guard let label else { return true }

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 7, weight: .heavy),
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph,
                .kern: -0.5
            ]
            let str = NSAttributedString(string: label, attributes: attrs)
            let textSize = str.size()
            let textRect = NSRect(
                x: 0,
                y: (rect.height - textSize.height) / 2 - 0.5,
                width: rect.width,
                height: textSize.height
            )
            str.draw(in: textRect)
            return true
        }
        composed.isTemplate = true
        return composed
    }
}
