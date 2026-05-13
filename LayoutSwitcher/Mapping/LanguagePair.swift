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

    /// Best-effort detection of known language pair from raw source language codes.
    static func detect(from primaryCode: String?, alternateCode: String?) -> LanguagePair? {
        let codes = Set([primaryCode, alternateCode].compactMap { $0?.lowercased() })
        if codes.contains("ru") || codes.contains("russian") { return .ruEn }
        if codes.contains("uk") || codes.contains("ukrainian") { return .uaEn }
        if codes.contains("ro") || codes.contains("romanian") { return .roEn }
        return nil
    }
}
