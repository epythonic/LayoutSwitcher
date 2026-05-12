import Foundation
import Observation

/// Persistent aggregate and daily counters for correction activity.
@MainActor
@Observable
final class UsageStats {
    private static let prefix = "stats."

    var autoSwitchesTotal: Int { didSet { persist() } }
    var manualSwitchesTotal: Int { didSet { persist() } }
    var wordsCommittedTotal: Int { didSet { persist() } }
    var charactersSavedTotal: Int { didSet { persist() } }

    var autoSwitchesToday: Int { didSet { persist() } }
    var manualSwitchesToday: Int { didSet { persist() } }
    var wordsCommittedToday: Int { didSet { persist() } }
    var charactersSavedToday: Int { didSet { persist() } }

    private var todayKey: String { didSet { persist() } }
    private let defaults: UserDefaults

    /// Loads persisted counters and applies day rollover if needed.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let d = defaults
        self.autoSwitchesTotal     = d.integer(forKey: Self.prefix + "autoTotal")
        self.manualSwitchesTotal   = d.integer(forKey: Self.prefix + "manualTotal")
        self.wordsCommittedTotal   = d.integer(forKey: Self.prefix + "wordsTotal")
        self.charactersSavedTotal  = d.integer(forKey: Self.prefix + "charsTotal")
        self.todayKey              = d.string(forKey: Self.prefix + "todayKey") ?? Self.dayString(Date())
        self.autoSwitchesToday     = d.integer(forKey: Self.prefix + "autoToday")
        self.manualSwitchesToday   = d.integer(forKey: Self.prefix + "manualToday")
        self.wordsCommittedToday   = d.integer(forKey: Self.prefix + "wordsToday")
        self.charactersSavedToday  = d.integer(forKey: Self.prefix + "charsToday")
        rolloverIfNeeded()
    }

    /// Records that one word token was committed by user input.
    func recordWordCommitted() {
        rolloverIfNeeded()
        wordsCommittedTotal += 1
        wordsCommittedToday += 1
    }

    /// Records one successful automatic correction and saved character count.
    func recordAutoSwitch(charactersSaved: Int) {
        rolloverIfNeeded()
        autoSwitchesTotal += 1
        autoSwitchesToday += 1
        charactersSavedTotal += charactersSaved
        charactersSavedToday += charactersSaved
    }

    /// Records one successful manual hotkey-based correction.
    func recordManualSwitch() {
        rolloverIfNeeded()
        manualSwitchesTotal += 1
        manualSwitchesToday += 1
    }

    /// Explicitly clears daily counters without touching totals.
    func resetTodayCounters() {
        autoSwitchesToday = 0
        manualSwitchesToday = 0
        wordsCommittedToday = 0
        charactersSavedToday = 0
    }

    /// Resets day-scoped counters when calendar day changes.
    private func rolloverIfNeeded() {
        let current = Self.dayString(Date())
        if current != todayKey {
            todayKey = current
            autoSwitchesToday = 0
            manualSwitchesToday = 0
            wordsCommittedToday = 0
            charactersSavedToday = 0
        }
    }

    /// Flushes all counters to `UserDefaults`.
    private func persist() {
        let d = defaults
        d.set(autoSwitchesTotal,    forKey: Self.prefix + "autoTotal")
        d.set(manualSwitchesTotal,  forKey: Self.prefix + "manualTotal")
        d.set(wordsCommittedTotal,  forKey: Self.prefix + "wordsTotal")
        d.set(charactersSavedTotal, forKey: Self.prefix + "charsTotal")
        d.set(todayKey,             forKey: Self.prefix + "todayKey")
        d.set(autoSwitchesToday,    forKey: Self.prefix + "autoToday")
        d.set(manualSwitchesToday,  forKey: Self.prefix + "manualToday")
        d.set(wordsCommittedToday,  forKey: Self.prefix + "wordsToday")
        d.set(charactersSavedToday, forKey: Self.prefix + "charsToday")
    }

    /// Stable day key formatter used for daily rollover boundaries.
    private static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
