import CoreGraphics

/// Ukrainian-specific overrides for `RuEnQwertyMapping`. Most Cyrillic keys
/// are identical to Russian, so the main table stores only EN/RU and UA looks
/// up the same row, falling back to the RU column. Listing the deltas here
/// lets future Ukrainian-only changes (e.g. apostrophe handling) live in one
/// dedicated file without touching the shared table.
extension RuEnQwertyMapping {
    /// Keycodes whose Ukrainian glyph differs from Russian.
    /// Format: `keyCode: <UA glyph>`. RU equivalents in comments.
    static let uaOverrides: [CGKeyCode: Character] = [
        1:  "і", // RU: ы
        30: "ї", // RU: ъ
        39: "є", // RU: э
        50: "ґ"  // RU: ё
    ]

    /// Resolves the Ukrainian glyph for a key by overlay-then-fallback:
    /// UA-specific override if listed, otherwise the Russian glyph from the
    /// shared table.
    static func ukCharacter(for keyCode: CGKeyCode, fallback russian: Character) -> Character {
        uaOverrides[keyCode] ?? russian
    }
}
