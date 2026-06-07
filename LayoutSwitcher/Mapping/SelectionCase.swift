import Foundation

/// Cycles the letter casing of a string: lowercase → UPPERCASE → Title Case → …
///
/// Pure and side-effect free so it can be unit-tested independently of the
/// selection read/replace machinery in `SelectionConverter`.
enum SelectionCase {
    /// Returns the next casing in the cycle, or nil when there is nothing to
    /// change (no cased letters, or the result would equal the input).
    static func cycled(_ text: String) -> String? {
        guard text.contains(where: { $0.isLetter }) else { return nil }

        let next: String
        if isAllLowercase(text) {
            next = text.uppercased()
        } else if isAllUppercase(text) {
            next = text.capitalized // Title Case
        } else {
            next = text.lowercased()
        }

        return next == text ? nil : next
    }

    /// True when every cased letter in the text is lowercase.
    private static func isAllLowercase(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter)
        return !letters.isEmpty && letters.allSatisfy(\.isLowercase)
    }

    /// True when every cased letter in the text is uppercase.
    private static func isAllUppercase(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter)
        return !letters.isEmpty && letters.allSatisfy(\.isUppercase)
    }
}
