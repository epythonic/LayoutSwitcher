import Foundation

/// Available system sounds for automatic-switch feedback.
enum SoundFeedbackKind: String, CaseIterable, Identifiable, Sendable {
    case tink
    case glass

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .tink:  String(localized: "sound.tink")
        case .glass: String(localized: "sound.glass")
        }
    }
}
