import Foundation

/// Remembers user-undone corrections so the same mistake is not auto-corrected again.
@MainActor
struct LearningCache {
    private static let key = "learning.cache.entries"
    private static let maxEntries = 50
    private let defaults: UserDefaults
    private let now: @MainActor () -> Date
    private let makeEntryID: @MainActor () -> UUID

    /// One learned suppression entry.
    private struct Entry: Codable, Equatable, Sendable {
        let original: String
        let corrected: String
        let sourceLanguage: String
        let targetLanguage: String
        let bundleID: String?
        let timestamp: Date
    }

    /// Public read-only representation of a learned entry for UI display.
    struct LearnedEntry: Identifiable, Equatable, Sendable {
        /// Stable row identity for SwiftUI lists during one presentation.
        let id: UUID
        /// Physical text originally typed before correction.
        let original: String
        /// Corrected text that the user later undid.
        let corrected: String
        /// Source language active when the original text was typed.
        let sourceLanguage: String
        /// Target language used for the correction.
        let targetLanguage: String
        /// Bundle identifier where the suppression applies, when known.
        let bundleID: String?
        /// Time when the undo was recorded.
        let timestamp: Date
    }

    private var entries: [Entry] {
        get {
            guard let data = defaults.data(forKey: Self.key),
                  let decoded = try? JSONDecoder().decode([Entry].self, from: data) else {
                return []
            }
            return decoded
        }
        nonmutating set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Self.key)
            }
        }
    }

    /// Creates a cache backed by injected defaults and clock.
    init(
        defaults: UserDefaults,
        now: @escaping @MainActor () -> Date,
        makeEntryID: @escaping @MainActor () -> UUID
    ) {
        self.defaults = defaults
        self.now = now
        self.makeEntryID = makeEntryID
    }

    /// Records that the user undid a specific correction, so future identical
    /// original→corrected switches are suppressed.
    func recordUndo(record: AutoSwitchRecord) {
        var current = entries
        let entry = Entry(
            original: record.original.map(\.unicode).joined(),
            corrected: record.corrected,
            sourceLanguage: record.sourceLanguage.rawValue,
            targetLanguage: record.targetLanguage.rawValue,
            bundleID: record.bundleID,
            timestamp: now()
        )
        current.removeAll { $0 == entry }
        current.insert(entry, at: 0)
        if current.count > Self.maxEntries {
            current.removeLast(current.count - Self.maxEntries)
        }
        entries = current
    }

    /// Returns true if an identical original→corrected pair was previously undone
    /// and should therefore be suppressed for the same app.
    func shouldSuppress(
        original: String,
        corrected: String,
        sourceLanguage: LanguageID,
        targetLanguage: LanguageID,
        bundleID: String?
    ) -> Bool {
        entries.contains(where: {
            $0.original == original
                && $0.corrected == corrected
                && $0.sourceLanguage == sourceLanguage.rawValue
                && $0.targetLanguage == targetLanguage.rawValue
                && $0.bundleID == bundleID
        })
    }

    /// Returns all learned entries ordered by most recent first.
    func allEntries() -> [LearnedEntry] {
        entries.map { LearnedEntry(
            id: makeEntryID(),
            original: $0.original,
            corrected: $0.corrected,
            sourceLanguage: $0.sourceLanguage,
            targetLanguage: $0.targetLanguage,
            bundleID: $0.bundleID,
            timestamp: $0.timestamp
        ) }
    }

    /// Removes the entry at the given index in the current list.
    func remove(at index: Int) {
        var current = entries
        guard index >= 0, index < current.count else { return }
        current.remove(at: index)
        entries = current
    }

    /// Removes all learned entries.
    func removeAll() {
        entries = []
    }
}
