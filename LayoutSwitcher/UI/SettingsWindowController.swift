import AppKit
import SwiftUI

/// Owns preferences window instance and injects runtime state into `SettingsView`.
@MainActor
final class SettingsWindowController: NSObject {
    /// Lazily created singleton preferences window.
    private var window: NSWindow?
    /// Shared settings model.
    private let appState: AppState
    /// Per-application exclusions model.
    private let exclusions: ExclusionList
    /// Usage statistics model.
    private let stats: UsageStats
    /// User English dictionary model.
    private let userEnglish: UserDictionary
    /// User Russian dictionary model.
    private let userRussian: UserDictionary
    /// User Ukrainian dictionary model.
    private let userUkrainian: UserDictionary
    /// User Romanian dictionary model.
    private let userRomanian: UserDictionary
    /// Keyboard input source manager.
    private let inputSources: InputSourceManager
    /// Hotkey binding registry.
    private let hotkeys: HotkeyRegistry
    /// Text auto-replace rule store.
    private let autoReplaceRules: AutoReplaceRules
    /// Per-application preferred layout model.
    private let perAppLayouts: PerAppLayoutPreferences
    /// Recent corrections history model.
    private let recents: RecentSwitches
    /// Learned corrections cache model.
    private let learningCache: LearningCache
    /// Launch-at-login service manager.
    private let launchAtLoginManager: LaunchAtLoginManager
    /// Opens the help window from the settings UI.
    private let openHelp: () -> Void

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
        autoReplaceRules: AutoReplaceRules,
        perAppLayouts: PerAppLayoutPreferences,
        recents: RecentSwitches,
        learningCache: LearningCache,
        launchAtLoginManager: LaunchAtLoginManager,
        openHelp: @escaping () -> Void
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
        self.autoReplaceRules = autoReplaceRules
        self.perAppLayouts = perAppLayouts
        self.recents = recents
        self.learningCache = learningCache
        self.launchAtLoginManager = launchAtLoginManager
        self.openHelp = openHelp
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
            autoReplaceRules: autoReplaceRules,
            perAppLayouts: perAppLayouts,
            recents: recents,
            learningCache: learningCache,
            launchAtLoginManager: launchAtLoginManager,
            openHelp: openHelp
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
