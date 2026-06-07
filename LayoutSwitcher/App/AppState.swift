import Foundation
import Observation

/// User-selectable durations for temporarily pausing automatic layout switching.
enum SnoozeDuration: Int, CaseIterable, Sendable {
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case sixtyMinutes = 60

    /// Duration in seconds used by the runtime snooze timer.
    var seconds: TimeInterval {
        TimeInterval(rawValue * 60)
    }

    /// Localized label shown in settings and hotkey feedback.
    var localizedTitle: String {
        switch self {
        case .fiveMinutes: String(localized: "snooze.5-minutes")
        case .fifteenMinutes: String(localized: "snooze.15-minutes")
        case .sixtyMinutes: String(localized: "snooze.60-minutes")
        }
    }
}

/// Observable application state shared by menu-bar UI, settings, and pipeline coordinators.
///
/// Persistent settings are written through `UserDefaults` in `didSet` observers,
/// while transient runtime state such as current layout, accessibility status, and
/// snooze deadlines stays main-actor isolated.
@MainActor
@Observable
final class AppState {
    private static let autoAddRomanianDiacriticsKey = "settings.autoAddRomanianDiacritics"
    private static let autoAddRussianYoKey = "settings.autoAddRussianYo"
    private static let correctDoubleCapitalsKey = "settings.correctDoubleCapitals"
    private static let correctDuplicateLettersKey = "settings.correctDuplicateLetters"
    private static let correctCommonTyposKey = "settings.correctCommonTypos"
    private static let correctSingleCharacterWordsKey = "settings.correctSingleCharacterWords"
    private static let autoExtendRecentAmbiguousKey = "settings.autoExtendRecentAmbiguous"
    private static let detectionSensitivityKey = "settings.detectionSensitivity"
    private static let detectionSensitivityByPairKey = "settings.detectionSensitivityByPair"
    private static let soundFeedbackEnabledKey = "settings.soundFeedbackEnabled"
    private static let soundFeedbackKindKey = "settings.soundFeedbackKind"
    private static let visualFeedbackEnabledKey = "settings.visualFeedbackEnabled"
    private static let snoozeDurationKey = "settings.snoozeDurationMinutes"
    private static let launchAtLoginKey = "settings.launchAtLogin"
    private static let activeLanguagePairKey = "settings.activeLanguagePair"
    private static let enabledLanguageDirectionsKey = "settings.enabledLanguageDirections"
    private let defaults: UserDefaults
    private let now: @MainActor () -> Date

    /// Master runtime switch for automatic layout correction.
    var isEnabled: Bool = true
    /// Enables automatic Romanian diacritic correction for plain Latin words.
    var autoAddRomanianDiacritics: Bool {
        didSet {
            defaults.set(autoAddRomanianDiacritics, forKey: Self.autoAddRomanianDiacriticsKey)
        }
    }
    /// Enables automatic Russian yo correction for unambiguous plain-e words.
    var autoAddRussianYo: Bool {
        didSet {
            defaults.set(autoAddRussianYo, forKey: Self.autoAddRussianYoKey)
        }
    }
    /// Enables correction of accidentally capitalized first two letters.
    var correctDoubleCapitals: Bool {
        didSet {
            defaults.set(correctDoubleCapitals, forKey: Self.correctDoubleCapitalsKey)
        }
    }
    /// Enables same-language correction of accidental adjacent duplicate letters.
    var correctDuplicateLetters: Bool {
        didSet {
            defaults.set(correctDuplicateLetters, forKey: Self.correctDuplicateLettersKey)
        }
    }
    /// Enables Cupertino-style same-language spelling typo correction.
    var correctCommonTypos: Bool {
        didSet {
            defaults.set(correctCommonTypos, forKey: Self.correctCommonTyposKey)
        }
    }
    /// Enables correction of single-character wrong-layout words.
    var correctSingleCharacterWords: Bool {
        didSet {
            defaults.set(correctSingleCharacterWords, forKey: Self.correctSingleCharacterWordsKey)
        }
    }
    /// Allows a strong correction to include recent ambiguous words before it.
    var autoExtendRecentAmbiguous: Bool {
        didSet {
            defaults.set(autoExtendRecentAmbiguous, forKey: Self.autoExtendRecentAmbiguousKey)
        }
    }
    /// Fallback sensitivity for pairs without an explicit override (seeded from the
    /// legacy global setting so existing installs keep their value).
    private let defaultDetectionSensitivity: DetectionSensitivity
    /// Per-language-pair sensitivity overrides.
    private var detectionSensitivityByPair: [LanguagePair: DetectionSensitivity] {
        didSet { persistDetectionSensitivityByPair() }
    }

    /// Sensitivity profile for the currently active language pair. Reading and
    /// writing this targets the active pair, so each pair keeps its own profile.
    var detectionSensitivity: DetectionSensitivity {
        get { detectionSensitivity(for: activeLanguagePair) }
        set { setDetectionSensitivity(newValue, for: activeLanguagePair) }
    }

    /// Sensitivity profile configured for a specific language pair.
    func detectionSensitivity(for pair: LanguagePair) -> DetectionSensitivity {
        detectionSensitivityByPair[pair] ?? defaultDetectionSensitivity
    }

    /// Sets the sensitivity profile for a specific language pair.
    func setDetectionSensitivity(_ sensitivity: DetectionSensitivity, for pair: LanguagePair) {
        detectionSensitivityByPair[pair] = sensitivity
    }
    /// Controls whether successful corrections play audible feedback.
    var soundFeedbackEnabled: Bool {
        didSet {
            defaults.set(soundFeedbackEnabled, forKey: Self.soundFeedbackEnabledKey)
        }
    }
    /// Selected sound feedback style.
    var soundFeedbackKind: SoundFeedbackKind {
        didSet {
            defaults.set(soundFeedbackKind.rawValue, forKey: Self.soundFeedbackKindKey)
        }
    }
    /// Controls whether successful corrections show visual feedback near the cursor.
    var visualFeedbackEnabled: Bool {
        didSet {
            defaults.set(visualFeedbackEnabled, forKey: Self.visualFeedbackEnabledKey)
        }
    }
    /// Duration used when the snooze hotkey starts a temporary pause.
    var snoozeDuration: SnoozeDuration {
        didSet {
            defaults.set(snoozeDuration.rawValue, forKey: Self.snoozeDurationKey)
        }
    }
    /// Desired launch-at-login setting reflected by the settings UI.
    var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Self.launchAtLoginKey)
        }
    }
    /// Single cross-layout language pair allowed to participate in automatic switching.
    var activeLanguagePair: LanguagePair {
        didSet {
            defaults.set(activeLanguagePair.rawValue, forKey: Self.activeLanguagePairKey)
        }
    }
    /// Cross-layout correction directions allowed by the user.
    var enabledLanguageDirections: Set<LanguageDirection> {
        didSet {
            persistEnabledLanguageDirections()
        }
    }
    /// Absolute date until which automatic switching is paused.
    var snoozedUntil: Date?
    /// Latest Accessibility trust snapshot shown in onboarding and status UI.
    var isAccessibilityGranted: Bool = false
    /// Identifier of the currently selected system keyboard layout, when known.
    var currentLayoutID: String?
    /// Last user-facing action summary displayed in the menu-bar popover.
    var lastActionDescription: String?

    /// Creates app state backed by injected defaults and clock.
    init(defaults: UserDefaults, now: @escaping @MainActor () -> Date) {
        self.defaults = defaults
        self.now = now
        self.autoAddRomanianDiacritics = defaults.bool(forKey: Self.autoAddRomanianDiacriticsKey)
        self.autoAddRussianYo = defaults.bool(forKey: Self.autoAddRussianYoKey)
        self.correctDoubleCapitals = defaults.bool(forKey: Self.correctDoubleCapitalsKey)
        self.correctDuplicateLetters = defaults.bool(forKey: Self.correctDuplicateLettersKey)
        self.correctCommonTypos = defaults.bool(forKey: Self.correctCommonTyposKey)
        self.correctSingleCharacterWords = defaults.bool(forKey: Self.correctSingleCharacterWordsKey)
        self.autoExtendRecentAmbiguous = defaults.bool(forKey: Self.autoExtendRecentAmbiguousKey)
        let legacySensitivityRaw = defaults.string(forKey: Self.detectionSensitivityKey)
        self.defaultDetectionSensitivity = legacySensitivityRaw.flatMap(DetectionSensitivity.init(rawValue:)) ?? .balanced
        self.detectionSensitivityByPair = Self.loadDetectionSensitivityByPair(from: defaults)
        self.soundFeedbackEnabled = defaults.object(forKey: Self.soundFeedbackEnabledKey) as? Bool ?? true
        let soundKindRaw = defaults.string(forKey: Self.soundFeedbackKindKey)
        self.soundFeedbackKind = soundKindRaw.flatMap(SoundFeedbackKind.init(rawValue:)) ?? .tink
        self.visualFeedbackEnabled = defaults.object(forKey: Self.visualFeedbackEnabledKey) as? Bool ?? true
        let durationRaw = defaults.integer(forKey: Self.snoozeDurationKey)
        self.snoozeDuration = SnoozeDuration(rawValue: durationRaw) ?? .fiveMinutes
        self.launchAtLogin = defaults.bool(forKey: Self.launchAtLoginKey)
        self.activeLanguagePair = Self.loadActiveLanguagePair(from: defaults)
        self.enabledLanguageDirections = Self.loadEnabledLanguageDirections(from: defaults)
    }

    /// Remaining active snooze interval, clearing expired pauses as they are observed.
    var activeSnoozeRemaining: TimeInterval? {
        guard let snoozedUntil else { return nil }
        let remaining = snoozedUntil.timeIntervalSince(now())
        guard remaining > 0 else {
            self.snoozedUntil = nil
            return nil
        }
        return remaining
    }

    /// Indicates whether auto-switching is currently paused by snooze.
    var isSnoozed: Bool {
        activeSnoozeRemaining != nil
    }

    /// Starts a snooze window using the configured duration.
    func startSnooze() {
        snoozedUntil = now().addingTimeInterval(snoozeDuration.seconds)
        let format = String(localized: "pipeline.result.snoozed-for")
        lastActionDescription = String(format: format, snoozeDuration.localizedTitle)
    }

    /// Clears any active snooze window immediately.
    func clearSnooze() {
        snoozedUntil = nil
        lastActionDescription = String(localized: "pipeline.result.snooze-cleared")
    }

    /// Returns whether a cross-layout automatic correction direction is enabled.
    func isLanguageDirectionEnabled(source: LanguageID, target: LanguageID) -> Bool {
        if source == target { return true }
        guard let direction = LanguageDirection(source: source, target: target) else {
            return false
        }
        return activeLanguagePair.directions.contains(direction)
            && enabledLanguageDirections.contains(direction)
    }

    /// Returns enabled cross-layout targets for the current source language.
    func enabledCrossLayoutTargets(from sourceLanguage: LanguageID) -> Set<LanguageID> {
        Set(activeLanguagePair.directions.filter {
            $0.source == sourceLanguage && enabledLanguageDirections.contains($0)
        }.map(\.target))
    }

    /// Updates the only cross-layout pair that automatic switching may consider.
    func setActiveLanguagePair(_ pair: LanguagePair) {
        activeLanguagePair = pair
    }

    /// Updates a single language direction and persists the resulting set.
    func setLanguageDirection(_ direction: LanguageDirection, isEnabled: Bool) {
        var directions = enabledLanguageDirections
        if isEnabled {
            directions.insert(direction)
        } else {
            directions.remove(direction)
        }
        enabledLanguageDirections = directions
    }

    private func persistEnabledLanguageDirections() {
        let rawValues = LanguageDirection.allCases
            .filter { enabledLanguageDirections.contains($0) }
            .map(\.rawValue)
        defaults.set(rawValues, forKey: Self.enabledLanguageDirectionsKey)
    }

    private static func loadEnabledLanguageDirections(from defaults: UserDefaults) -> Set<LanguageDirection> {
        guard let rawValues = defaults.array(forKey: Self.enabledLanguageDirectionsKey) as? [String] else {
            return Set(LanguageDirection.allCases)
        }
        return Set(rawValues.compactMap(LanguageDirection.init(rawValue:)))
    }

    private static func loadActiveLanguagePair(from defaults: UserDefaults) -> LanguagePair {
        defaults.string(forKey: Self.activeLanguagePairKey).flatMap(LanguagePair.init(rawValue:)) ?? .ruEn
    }

    private func persistDetectionSensitivityByPair() {
        let raw = detectionSensitivityByPair.reduce(into: [String: String]()) { result, entry in
            result[entry.key.rawValue] = entry.value.rawValue
        }
        defaults.set(raw, forKey: Self.detectionSensitivityByPairKey)
    }

    private static func loadDetectionSensitivityByPair(from defaults: UserDefaults) -> [LanguagePair: DetectionSensitivity] {
        guard let raw = defaults.dictionary(forKey: Self.detectionSensitivityByPairKey) as? [String: String] else {
            return [:]
        }
        return raw.reduce(into: [LanguagePair: DetectionSensitivity]()) { result, entry in
            if let pair = LanguagePair(rawValue: entry.key),
               let sensitivity = DetectionSensitivity(rawValue: entry.value) {
                result[pair] = sensitivity
            }
        }
    }
}
