import Foundation

/// Concrete pair of system input sources representing a switchable language pair.
struct LayoutPair: Hashable {
    let primary: InputSource
    let alternate: InputSource
    let languagePair: LanguagePair

    /// Returns the opposite side of pair for given source, or `nil` when source is unrelated.
    func opposite(of source: InputSource) -> InputSource? {
        if source.id == primary.id { return alternate }
        if source.id == alternate.id { return primary }
        return nil
    }
}

/// Utility that infers candidate layout pairs from currently enabled system input sources.
enum LayoutPairResolver {
    /// Attempts to build known language pairs against an enabled English layout.
    static func autoDetect(from sources: [InputSource]) -> [LayoutPair] {
        let enabled = sources.filter(\.isEnabled).filter(\.isSelectable)
        guard let english = enabled.first(where: { ($0.primaryLanguage ?? "").lowercased().hasPrefix("en") }) else {
            return []
        }

        let candidates: [(LanguagePair, [String])] = [
            (.ruEn, ["ru"]),
            (.uaEn, ["uk"]),
            (.roEn, ["ro"])
        ]

        return candidates.compactMap { pair, prefixes in
            guard let primary = enabled.first(where: { source in
                let lang = (source.primaryLanguage ?? "").lowercased()
                return prefixes.contains { lang.hasPrefix($0) }
            }) else { return nil }
            return LayoutPair(primary: primary, alternate: english, languagePair: pair)
        }
    }
}
