import Foundation

/// User-visible category of an automatic correction.
enum CorrectionFeedbackKind: String, CaseIterable, Sendable {
    case layoutSwitch
    case romanianDiacritic
    case russianYo
    case doubleCapital
    case duplicateLetter
    case cupertino

    /// Distinct macOS system sound name used for this correction category.
    var systemSoundName: String {
        switch self {
        case .layoutSwitch: "Tink"
        case .romanianDiacritic: "Purr"
        case .russianYo: "Ping"
        case .doubleCapital: "Glass"
        case .duplicateLetter: "Pop"
        case .cupertino: "Funk"
        }
    }

    /// Short status-bar badge used while visual feedback is flashing.
    var visualBadge: String {
        switch self {
        case .layoutSwitch: "AS"
        case .romanianDiacritic: "RO"
        case .russianYo: "YO"
        case .doubleCapital: "AA"
        case .duplicateLetter: "DD"
        case .cupertino: "CU"
        }
    }

    /// Localized last-action summary displayed in the status menu.
    func localizedSummary(original: String, corrected: String) -> String {
        let key: LocalizedStringResource = {
            switch self {
            case .layoutSwitch: "pipeline.result.auto-switch"
            case .romanianDiacritic: "pipeline.result.romanian-diacritic"
            case .russianYo: "pipeline.result.russian-yo"
            case .doubleCapital: "pipeline.result.double-capital"
            case .duplicateLetter: "pipeline.result.duplicate-letter"
            case .cupertino: "pipeline.result.cupertino"
            }
        }()
        return String(format: String(localized: key), original, corrected)
    }
}
