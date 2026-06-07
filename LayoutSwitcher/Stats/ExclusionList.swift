import AppKit
import Foundation
import Observation
import os

/// Persistent allow/deny list of applications excluded from auto-switch corrections.
@MainActor
@Observable
final class ExclusionList {
    private static let logger = Logger(subsystem: "GM.LayoutSwitcher", category: "Exclusions")
    private static let defaultsKey = "exclusions.bundleIDs"
    private static let legacyDefaultsKey = "exclusionBundleIDs"
    private static let defaultSeedAppliedKey = "exclusions.defaultSeedApplied"

    /// Current and legacy bundle identifiers for self-exclusion.
    static let selfBundleIDs: Set<String> = [
        "GM.LayoutSwitcher",
        "GIH.LayoutSwitcher"
    ]

    /// Recommended third-party and system bundle identifiers seeded once on first launch.
    private static let recommendedBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.apple.Console",
        "com.apple.ActivityMonitor",
        "com.apple.ScriptEditor2",
        "com.apple.Automator",
        "com.apple.shortcuts",
        "com.googlecode.iterm2",
        "com.microsoft.VSCode",
        "com.sublimetext.4",
        "com.jetbrains.intellij",
        "com.jetbrains.pycharm",
        "com.jetbrains.WebStorm",
        "com.jetbrains.AppCode",
        "com.1password.1password",
        "com.agilebits.onepassword7"
    ]

    /// Recommended bundle identifiers seeded once on first launch.
    static let defaults: Set<String> = ExclusionList.recommendedBundleIDs.union(ExclusionList.selfBundleIDs)

    private(set) var bundleIDs: Set<String>
    private let userDefaults: UserDefaults
    private let localizedNameProvider: @MainActor (String) -> String?

    /// Loads persisted exclusions or seeds the first-run recommended set using the provided workspace.
    convenience init(
        defaults: UserDefaults,
        workspace: NSWorkspace
    ) {
        self.init(
            defaults: defaults,
            localizedNameProvider: { bundleID in
                Self.localizedName(for: bundleID, workspace: workspace)
            }
        )
    }

    /// Loads persisted exclusions or seeds the first-run recommended set with injectable name lookup.
    init(
        defaults: UserDefaults,
        localizedNameProvider: @escaping @MainActor (String) -> String?
    ) {
        self.userDefaults = defaults
        self.localizedNameProvider = localizedNameProvider
        if let stored = Self.loadBundleIDs(from: defaults) {
            self.bundleIDs = stored
            Self.markDefaultSeedApplied(in: defaults)
        } else if defaults.bool(forKey: Self.defaultSeedAppliedKey) {
            self.bundleIDs = []
            persist()
        } else {
            self.bundleIDs = Self.defaults
            persist()
            Self.markDefaultSeedApplied(in: defaults)
        }
    }

    /// Checks whether a given app bundle ID is currently excluded.
    func contains(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleIDs.contains(bundleID)
    }

    /// Adds bundle ID to exclusion list and persists changes.
    func add(_ bundleID: String) {
        guard !bundleID.isEmpty else { return }
        bundleIDs.insert(bundleID)
        persist()
    }

    /// Removes bundle ID from exclusion list and persists changes.
    func remove(_ bundleID: String) {
        bundleIDs.remove(bundleID)
        persist()
    }

    /// Returns exclusions sorted with localized app names for settings UI.
    func sortedEntries() -> [(bundleID: String, name: String)] {
        bundleIDs.sorted().map { id in
            (id, localizedNameProvider(id) ?? id)
        }
    }

    /// Resolves localized application display name for bundle identifier.
    static func localizedName(for bundleID: String) -> String? {
        localizedName(for: bundleID, workspace: .shared)
    }

    /// Resolves localized application display name for bundle identifier using the provided workspace.
    static func localizedName(for bundleID: String, workspace: NSWorkspace) -> String? {
        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url) else {
            return nil
        }
        return bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle.infoDictionary?["CFBundleName"] as? String
    }

    /// Persists exclusion list to `UserDefaults`.
    private func persist() {
        userDefaults.set(Array(bundleIDs), forKey: Self.defaultsKey)
        userDefaults.removeObject(forKey: Self.legacyDefaultsKey)
    }

    private static func loadBundleIDs(from defaults: UserDefaults) -> Set<String>? {
        if let stored = defaults.array(forKey: Self.defaultsKey) as? [String] {
            return Set(stored)
        }
        guard let legacy = defaults.array(forKey: Self.legacyDefaultsKey) as? [String] else {
            return nil
        }
        let migrated = Set(legacy)
        defaults.set(Array(migrated), forKey: Self.defaultsKey)
        return migrated
    }

    private static func markDefaultSeedApplied(in defaults: UserDefaults) {
        defaults.set(true, forKey: Self.defaultSeedAppliedKey)
    }
}
