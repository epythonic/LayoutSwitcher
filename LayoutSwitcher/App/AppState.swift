import Foundation
import Observation

enum SnoozeDuration: Int, CaseIterable {
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case sixtyMinutes = 60

    var seconds: TimeInterval {
        TimeInterval(rawValue * 60)
    }

    var localizedTitle: String {
        switch self {
        case .fiveMinutes: String(localized: "snooze.5-minutes")
        case .fifteenMinutes: String(localized: "snooze.15-minutes")
        case .sixtyMinutes: String(localized: "snooze.60-minutes")
        }
    }
}

@MainActor
@Observable
final class AppState {
    private static let autoAddRomanianDiacriticsKey = "settings.autoAddRomanianDiacritics"
    private static let correctSingleCharacterWordsKey = "settings.correctSingleCharacterWords"
    private static let autoExtendRecentAmbiguousKey = "settings.autoExtendRecentAmbiguous"
    private static let detectionSensitivityKey = "settings.detectionSensitivity"
    private static let soundFeedbackEnabledKey = "settings.soundFeedbackEnabled"
    private static let soundFeedbackKindKey = "settings.soundFeedbackKind"
    private static let visualFeedbackEnabledKey = "settings.visualFeedbackEnabled"
    private static let snoozeDurationKey = "settings.snoozeDurationMinutes"
    private static let launchAtLoginKey = "settings.launchAtLogin"
    private let defaults: UserDefaults
    private let now: () -> Date

    var isEnabled: Bool = true
    var autoAddRomanianDiacritics: Bool {
        didSet {
            defaults.set(autoAddRomanianDiacritics, forKey: Self.autoAddRomanianDiacriticsKey)
        }
    }
    var correctSingleCharacterWords: Bool {
        didSet {
            defaults.set(correctSingleCharacterWords, forKey: Self.correctSingleCharacterWordsKey)
        }
    }
    var autoExtendRecentAmbiguous: Bool {
        didSet {
            defaults.set(autoExtendRecentAmbiguous, forKey: Self.autoExtendRecentAmbiguousKey)
        }
    }
    var detectionSensitivity: DetectionSensitivity {
        didSet {
            defaults.set(detectionSensitivity.rawValue, forKey: Self.detectionSensitivityKey)
        }
    }
    var soundFeedbackEnabled: Bool {
        didSet {
            defaults.set(soundFeedbackEnabled, forKey: Self.soundFeedbackEnabledKey)
        }
    }
    var soundFeedbackKind: SoundFeedbackKind {
        didSet {
            defaults.set(soundFeedbackKind.rawValue, forKey: Self.soundFeedbackKindKey)
        }
    }
    var visualFeedbackEnabled: Bool {
        didSet {
            defaults.set(visualFeedbackEnabled, forKey: Self.visualFeedbackEnabledKey)
        }
    }
    var snoozeDuration: SnoozeDuration {
        didSet {
            defaults.set(snoozeDuration.rawValue, forKey: Self.snoozeDurationKey)
        }
    }
    var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Self.launchAtLoginKey)
        }
    }
    var snoozedUntil: Date?
    var isAccessibilityGranted: Bool = false
    var currentLayoutID: String?
    var lastActionDescription: String?

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        self.autoAddRomanianDiacritics = defaults.bool(forKey: Self.autoAddRomanianDiacriticsKey)
        self.correctSingleCharacterWords = defaults.bool(forKey: Self.correctSingleCharacterWordsKey)
        self.autoExtendRecentAmbiguous = defaults.bool(forKey: Self.autoExtendRecentAmbiguousKey)
        let sensitivityRaw = defaults.string(forKey: Self.detectionSensitivityKey)
        self.detectionSensitivity = sensitivityRaw.flatMap(DetectionSensitivity.init(rawValue:)) ?? .balanced
        self.soundFeedbackEnabled = defaults.object(forKey: Self.soundFeedbackEnabledKey) as? Bool ?? true
        let soundKindRaw = defaults.string(forKey: Self.soundFeedbackKindKey)
        self.soundFeedbackKind = soundKindRaw.flatMap(SoundFeedbackKind.init(rawValue:)) ?? .tink
        self.visualFeedbackEnabled = defaults.object(forKey: Self.visualFeedbackEnabledKey) as? Bool ?? true
        let durationRaw = defaults.integer(forKey: Self.snoozeDurationKey)
        self.snoozeDuration = SnoozeDuration(rawValue: durationRaw) ?? .fiveMinutes
        self.launchAtLogin = defaults.bool(forKey: Self.launchAtLoginKey)
    }

    var activeSnoozeRemaining: TimeInterval? {
        guard let snoozedUntil else { return nil }
        let remaining = snoozedUntil.timeIntervalSince(now())
        guard remaining > 0 else {
            self.snoozedUntil = nil
            return nil
        }
        return remaining
    }

    var isSnoozed: Bool {
        activeSnoozeRemaining != nil
    }

    func startSnooze() {
        snoozedUntil = now().addingTimeInterval(snoozeDuration.seconds)
        let format = String(localized: "pipeline.result.snoozed-for")
        lastActionDescription = String(format: format, snoozeDuration.localizedTitle)
    }

    func clearSnooze() {
        snoozedUntil = nil
        lastActionDescription = String(localized: "pipeline.result.snooze-cleared")
    }
}
