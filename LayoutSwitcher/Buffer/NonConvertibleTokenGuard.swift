import Foundation

/// Identifies technical tokens that must never be auto-converted by layout detection.
enum NonConvertibleTokenGuard {
    private static let urlPrefixes = ["http://", "https://", "ftp://", "ssh://", "www."]
    private static let pathPrefixes = ["/", "~/", "./", "../"]
    private static let technicalBoundaryCharacters: Set<Character> = ["@", ".", "/", "\\", ":", "_"]

    /// Returns true when a token looks like a URL, email, handle, path, package name, or similar identifier.
    static func shouldKeep(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace }) else { return false }

        let lowercased = trimmed.lowercased()
        if urlPrefixes.contains(where: { lowercased.hasPrefix($0) }) {
            return true
        }
        if pathPrefixes.contains(where: { lowercased.hasPrefix($0) }) {
            return true
        }
        if trimmed.contains("/") || trimmed.contains("\\") {
            return true
        }
        if trimmed.contains("@") {
            return true
        }
        if isDottedIdentifier(trimmed) {
            return true
        }
        return false
    }

    /// Returns true for punctuation that starts or continues a technical compound token in the live pipeline.
    static func isTechnicalBoundary(_ character: Character) -> Bool {
        technicalBoundaryCharacters.contains(character)
    }

    /// Returns true when all dot-separated segments look like code/package/domain identifiers.
    private static func isDottedIdentifier(_ token: String) -> Bool {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2, !segments.contains(where: { $0.isEmpty }) else { return false }
        return segments.allSatisfy { segment in
            segment.unicodeScalars.allSatisfy { scalar in
                CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-"
            }
        }
    }
}
