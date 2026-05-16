import Foundation

/// Internal language identifier used by detector, dictionaries, and keyboard mapping.
enum LanguageID: String, Hashable, CaseIterable, Sendable {
    case en
    case ru
    case uk
    case ro

    /// Maps an input-source language tag (for example `en-US`) to a supported language.
    init?(inputSourceLanguageCode code: String?) {
        guard let code = code?.lowercased() else { return nil }
        let prefix = String(code.prefix(2))
        self.init(rawValue: prefix)
    }

    /// Localized display name shown in diagnostics and UI.
    var localizedTitle: String {
        switch self {
        case .en: String(localized: "language.english")
        case .ru: String(localized: "language.russian")
        case .ro: String(localized: "language.romanian")
        case .uk: String(localized: "language.ukrainian")
        }
    }
}

/// User-configurable cross-layout correction direction.
enum LanguageDirection: String, CaseIterable, Hashable, Identifiable, Sendable {
    case enToRu = "en-ru"
    case ruToEn = "ru-en"
    case enToUk = "en-uk"
    case ukToEn = "uk-en"
    case enToRo = "en-ro"
    case roToEn = "ro-en"

    /// Stable identity used by SwiftUI lists and persisted defaults.
    var id: String { rawValue }

    /// Source language that the detector interprets as currently active.
    var source: LanguageID {
        switch self {
        case .enToRu, .enToUk, .enToRo: .en
        case .ruToEn: .ru
        case .ukToEn: .uk
        case .roToEn: .ro
        }
    }

    /// Target language that an automatic layout correction may retype into.
    var target: LanguageID {
        switch self {
        case .enToRu: .ru
        case .ruToEn, .ukToEn, .roToEn: .en
        case .enToUk: .uk
        case .enToRo: .ro
        }
    }

    /// Localized label shown in Preferences.
    var localizedTitle: String {
        String(
            format: NSLocalizedString("%@ → %@", comment: "Two language names separated by a right arrow."),
            source.localizedTitle,
            target.localizedTitle
        )
    }

    /// Builds a supported direction from source and target languages.
    init?(source: LanguageID, target: LanguageID) {
        guard let direction = Self.allCases.first(where: { $0.source == source && $0.target == target }) else {
            return nil
        }
        self = direction
    }
}

/// Supported layout-switching pairs where English acts as alternate keyboard.
enum LanguagePair: String, Hashable, CaseIterable, Sendable {
    case ruEn
    case uaEn
    case roEn

    /// Returns canonical (primary, alternate) language tuple for pair.
    var languages: (primary: LanguageID, alternate: LanguageID) {
        switch self {
        case .ruEn: return (.ru, .en)
        case .uaEn: return (.uk, .en)
        case .roEn: return (.ro, .en)
        }
    }

    /// Bidirectional user-facing correction directions for the pair.
    var directions: [LanguageDirection] {
        let languages = languages
        return [
            LanguageDirection(source: languages.alternate, target: languages.primary),
            LanguageDirection(source: languages.primary, target: languages.alternate)
        ].compactMap { $0 }
    }

    /// Localized label shown in Preferences.
    var localizedTitle: String {
        let languages = languages
        return String(
            format: NSLocalizedString("%@ ↔ %@", comment: "Two language names separated by a bidirectional arrow."),
            languages.primary.localizedTitle,
            languages.alternate.localizedTitle
        )
    }

    /// Best-effort detection of known language pair from raw source language codes.
    static func detect(from primaryCode: String?, alternateCode: String?) -> LanguagePair? {
        let codes = Set([primaryCode, alternateCode].compactMap { $0?.lowercased() })
        if codes.contains("ru") || codes.contains("russian") { return .ruEn }
        if codes.contains("uk") || codes.contains("ukrainian") { return .uaEn }
        if codes.contains("ro") || codes.contains("romanian") { return .roEn }
        return nil
    }
}
