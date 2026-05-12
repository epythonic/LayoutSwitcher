import AppKit
import Foundation
import Observation
import os

/// Persistent allow/deny list of applications excluded from auto-switch corrections.
@MainActor
@Observable
final class ExclusionList {
    private static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "Exclusions")
    private static let defaultsKey = "exclusionBundleIDs"

    /// Baseline excluded bundle identifiers (terminals, IDEs, password managers, this app).
    static let defaults: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.microsoft.VSCode",
        "com.sublimetext.4",
        "com.jetbrains.intellij",
        "com.jetbrains.pycharm",
        "com.jetbrains.WebStorm",
        "com.jetbrains.AppCode",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "GIH.LayoutSwitcher"
    ]

    private(set) var bundleIDs: Set<String>
    private let defaults: UserDefaults

    /// Loads persisted exclusions or initializes with default set.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.array(forKey: Self.defaultsKey) as? [String] {
            self.bundleIDs = Set(stored)
        } else {
            self.bundleIDs = Self.defaults
            persist()
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
            (id, Self.localizedName(for: id) ?? id)
        }
    }

    /// Resolves localized application display name for bundle identifier.
    static func localizedName(for bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url) else {
            return nil
        }
        return bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle.infoDictionary?["CFBundleName"] as? String
    }

    /// Persists exclusion list to `UserDefaults`.
    private func persist() {
        defaults.set(Array(bundleIDs), forKey: Self.defaultsKey)
    }
}
