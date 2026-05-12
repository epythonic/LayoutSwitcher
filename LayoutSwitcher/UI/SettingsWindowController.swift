import AppKit
import SwiftUI

/// Owns preferences window instance and injects runtime state into `SettingsView`.
@MainActor
final class SettingsWindowController: NSObject {
    private var window: NSWindow?
    private let appState: AppState
    private let exclusions: ExclusionList
    private let stats: UsageStats
    private let userEnglish: UserDictionary
    private let userRussian: UserDictionary
    private let userUkrainian: UserDictionary
    private let userRomanian: UserDictionary
    private let inputSources: InputSourceManager
    private let hotkeys: HotkeyRegistry
    private let perAppLayouts: PerAppLayoutPreferences
    private let recents: RecentSwitches
    private let learningCache: LearningCache
    private let launchAtLoginManager: LaunchAtLoginManager

    /// Creates settings window controller with all shared state dependencies.
    init(
        appState: AppState,
        exclusions: ExclusionList,
        stats: UsageStats,
        userEnglish: UserDictionary,
        userRussian: UserDictionary,
        userUkrainian: UserDictionary,
        userRomanian: UserDictionary,
        inputSources: InputSourceManager,
        hotkeys: HotkeyRegistry,
        perAppLayouts: PerAppLayoutPreferences,
        recents: RecentSwitches,
        learningCache: LearningCache,
        launchAtLoginManager: LaunchAtLoginManager
    ) {
        self.appState = appState
        self.exclusions = exclusions
        self.stats = stats
        self.userEnglish = userEnglish
        self.userRussian = userRussian
        self.userUkrainian = userUkrainian
        self.userRomanian = userRomanian
        self.inputSources = inputSources
        self.hotkeys = hotkeys
        self.perAppLayouts = perAppLayouts
        self.recents = recents
        self.learningCache = learningCache
        self.launchAtLoginManager = launchAtLoginManager
    }

    /// Opens preferences window or brings existing one to front.
    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = SettingsView(
            appState: appState,
            exclusions: exclusions,
            stats: stats,
            userEnglish: userEnglish,
            userRussian: userRussian,
            userUkrainian: userUkrainian,
            userRomanian: userRomanian,
            inputSources: inputSources,
            hotkeys: hotkeys,
            perAppLayouts: perAppLayouts,
            recents: recents,
            learningCache: learningCache,
            launchAtLoginManager: launchAtLoginManager
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "settings.window.preferences")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

extension SettingsWindowController: NSWindowDelegate {
    /// Reserved for future close-side effects.
    func windowWillClose(_ notification: Notification) {}
}
