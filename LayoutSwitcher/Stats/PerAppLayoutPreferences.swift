import AppKit
import Foundation
import Observation
import os

/// Persistent mapping of `bundleID → input source ID` for "preferred layout per app".
/// On focus change the pipeline asks this store for the target app's preferred layout
/// and selects it via `InputSourceManager` — preventing typing-in-wrong-layout entirely.
@MainActor
@Observable
final class PerAppLayoutPreferences {
    private static let logger = Logger(subsystem: "GM.LayoutSwitcher", category: "PerAppLayout")
    private static let defaultsKey = "settings.perAppLayoutPreferences"

    private(set) var entries: [String: String]
    private let defaults: UserDefaults
    private let appNameProvider: @MainActor (String) -> String?

    /// Loads persisted mapping from defaults (empty on first launch).
    /// Tries Codable JSON first, falls back to the legacy plist `[String: String]`
    /// dictionary format so pre-Codable data isn't lost on upgrade.
    init(
        defaults: UserDefaults,
        appNameProvider: @escaping @MainActor (String) -> String? = { _ in nil }
    ) {
        self.defaults = defaults
        self.appNameProvider = appNameProvider
        self.entries = Self.load(from: defaults)
    }

    /// Returns preferred input source ID for given bundle, if any.
    func preferredLayout(for bundleID: String?) -> String? {
        guard let bundleID else { return nil }
        return entries[bundleID]
    }

    /// Assigns or updates preferred layout for an app.
    func set(layoutID: String, for bundleID: String) {
        guard !bundleID.isEmpty, !layoutID.isEmpty else { return }
        entries[bundleID] = layoutID
        persist()
    }

    /// Removes preferred layout mapping for an app.
    func remove(_ bundleID: String) {
        entries.removeValue(forKey: bundleID)
        persist()
    }

    /// Returns mappings sorted by localized app name for settings UI.
    func sortedEntries() -> [(bundleID: String, layoutID: String, appName: String)] {
        entries.map { id, layout in
            (id, layout, appNameProvider(id) ?? id)
        }
        .sorted { $0.appName.localizedCompare($1.appName) == .orderedAscending }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(entries)
            defaults.set(data, forKey: Self.defaultsKey)
        } catch {
            Self.logger.error("persist failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from defaults: UserDefaults) -> [String: String] {
        if let data = defaults.data(forKey: Self.defaultsKey) {
            if let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                return decoded
            }
        }
        if let legacy = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] {
            return legacy
        }
        return [:]
    }
}
