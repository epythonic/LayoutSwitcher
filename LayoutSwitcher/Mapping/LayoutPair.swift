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

/// Sendable metadata-only layout pair for UI and read-only flows.
struct LayoutPairSnapshot: Hashable, Sendable {
    let primary: InputSourceSnapshot
    let alternate: InputSourceSnapshot
    let languagePair: LanguagePair
}

/// Utility that infers candidate layout pairs from currently enabled system input sources.
enum LayoutPairResolver {
    /// Attempts to build known language pairs against an enabled English layout.
    static func autoDetect(from sources: [InputSource]) -> [LayoutPair] {
        autoDetectPairs(
            from: sources,
            isEnabled: { $0.isEnabled },
            isSelectable: { $0.isSelectable },
            primaryLanguage: { $0.primaryLanguage }
        ) { primary, english, pair in
            LayoutPair(primary: primary, alternate: english, languagePair: pair)
        }
    }

    /// Attempts to build known language pairs from metadata-only snapshots.
    static func autoDetectSnapshots(from sources: [InputSourceSnapshot]) -> [LayoutPairSnapshot] {
        autoDetectPairs(
            from: sources,
            isEnabled: { $0.isEnabled },
            isSelectable: { $0.isSelectable },
            primaryLanguage: { $0.primaryLanguage }
        ) { primary, english, pair in
            LayoutPairSnapshot(primary: primary, alternate: english, languagePair: pair)
        }
    }

    private static func autoDetectPairs<Source, Pair>(
        from sources: [Source],
        isEnabled: (Source) -> Bool,
        isSelectable: (Source) -> Bool,
        primaryLanguage: (Source) -> String?,
        makePair: (Source, Source, LanguagePair) -> Pair
    ) -> [Pair] {
        let enabled = sources.filter { isEnabled($0) && isSelectable($0) }
        guard let english = enabled.first(where: { (primaryLanguage($0) ?? "").lowercased().hasPrefix("en") }) else {
            return []
        }

        let candidates: [(LanguagePair, [String])] = [
            (.ruEn, ["ru"]),
            (.uaEn, ["uk"]),
            (.roEn, ["ro"])
        ]

        return candidates.compactMap { pair, prefixes in
            guard let primary = enabled.first(where: { source in
                let lang = (primaryLanguage(source) ?? "").lowercased()
                return prefixes.contains { lang.hasPrefix($0) }
            }) else { return nil }
            return makePair(primary, english, pair)
        }
    }
}
