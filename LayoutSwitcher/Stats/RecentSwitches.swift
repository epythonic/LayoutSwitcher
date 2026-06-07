import Foundation
import Observation
import os

/// Snapshot describing one successful auto/manual correction.
struct RecentSwitchEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let original: String
    let corrected: String
    let bundleID: String?
    let bundleName: String?
    let kind: Kind
    let timestamp: Date

    /// Indicates whether correction was initiated automatically or by hotkey.
    enum Kind: String, Codable, Sendable {
        case auto
        case manual
    }

    init(
        id: UUID,
        original: String,
        corrected: String,
        bundleID: String?,
        bundleName: String?,
        kind: Kind,
        timestamp: Date
    ) {
        self.id = id
        self.original = original
        self.corrected = corrected
        self.bundleID = bundleID
        self.bundleName = bundleName
        self.kind = kind
        self.timestamp = timestamp
    }
}

/// Persisted bounded buffer of recently applied corrections for menu/history display.
/// Survives app restarts via JSON in UserDefaults; FIFO-trimmed to `capacity` entries.
@MainActor
@Observable
final class RecentSwitches {
    private static let logger = Logger(subsystem: "GM.LayoutSwitcher", category: "RecentSwitches")
    private static let defaultsKey = "recentSwitches.entries"
    private static let legacyDefaultsKey = "recentSwitches"

    private(set) var entries: [RecentSwitchEntry] = []
    private let capacity: Int = 200
    private let defaults: UserDefaults
    private let makeEntryID: @MainActor () -> UUID

    /// Loads persisted history (empty on first launch / decode failure).
    init(
        defaults: UserDefaults,
        makeEntryID: @escaping @MainActor () -> UUID
    ) {
        self.defaults = defaults
        self.makeEntryID = makeEntryID
        self.entries = Self.load(from: defaults)
    }

    /// Inserts a new entry with an injected identifier, then persists it.
    func record(
        original: String,
        corrected: String,
        bundleID: String?,
        bundleName: String?,
        kind: RecentSwitchEntry.Kind,
        timestamp: Date
    ) {
        record(RecentSwitchEntry(
            id: makeEntryID(),
            original: original,
            corrected: corrected,
            bundleID: bundleID,
            bundleName: bundleName,
            kind: kind,
            timestamp: timestamp
        ))
    }

    /// Inserts new entry at head, trims tail to capacity, persists to defaults.
    func record(_ entry: RecentSwitchEntry) {
        entries.insert(entry, at: 0)
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
        persist()
    }

    /// Clears all remembered recent entries (and removes them from disk).
    func clear() {
        entries.removeAll()
        persist()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(entries)
            defaults.set(data, forKey: Self.defaultsKey)
            defaults.removeObject(forKey: Self.legacyDefaultsKey)
        } catch {
            Self.logger.error("persist failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from defaults: UserDefaults) -> [RecentSwitchEntry] {
        guard let data = defaults.data(forKey: Self.defaultsKey) ?? defaults.data(forKey: Self.legacyDefaultsKey) else {
            return []
        }
        do {
            let entries = try JSONDecoder().decode([RecentSwitchEntry].self, from: data)
            if defaults.data(forKey: Self.defaultsKey) == nil {
                defaults.set(data, forKey: Self.defaultsKey)
            }
            return entries
        } catch {
            Self.logger.error("load failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
