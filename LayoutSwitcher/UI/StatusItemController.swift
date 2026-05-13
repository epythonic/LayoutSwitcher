import AppKit
import os

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let appState: AppState
    private let permission: AccessibilityPermission
    private let recents: RecentSwitches
    private let exclusions: ExclusionList
    private let presentationDetector: PresentationModeDetector?
    private let openSettings: () -> Void
    private let openOnboarding: () -> Void
    private let openHelp: () -> Void
    private var isSecureTextField = false
    private var isSecureInputGlobal = false
    private var lastLanguageCode: String?

    init(
        appState: AppState,
        permission: AccessibilityPermission,
        recents: RecentSwitches,
        exclusions: ExclusionList,
        presentationDetector: PresentationModeDetector? = nil,
        openSettings: @escaping () -> Void,
        openOnboarding: @escaping () -> Void,
        openHelp: @escaping () -> Void
    ) {
        self.appState = appState
        self.permission = permission
        self.recents = recents
        self.exclusions = exclusions
        self.presentationDetector = presentationDetector
        self.openSettings = openSettings
        self.openOnboarding = openOnboarding
        self.openHelp = openHelp
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
        statusItem.menu = buildMenu()
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            AppDelegate.logger.error("StatusItem button is nil — menu bar item not created")
            return
        }
        button.image = statusImage(for: appState.currentLayoutID)
        button.imagePosition = .imageLeft
        button.title = ""
        button.toolTip = String(localized: "settings.about.title")
    }

    func updateSecureTextFieldState(_ isSecure: Bool) {
        guard isSecureTextField != isSecure else { return }
        isSecureTextField = isSecure
        updateLayoutBadge(lastLanguageCode)
    }

    func updateGlobalSecureInputState(_ isSecure: Bool) {
        guard isSecureInputGlobal != isSecure else { return }
        isSecureInputGlobal = isSecure
        updateLayoutBadge(lastLanguageCode)
    }

    func updateLayoutBadge(_ languageCode: String?) {
        lastLanguageCode = languageCode
        guard let button = statusItem.button else { return }
        let badge: String
        if let remaining = appState.activeSnoozeRemaining {
            badge = "P\(max(1, Int(ceil(remaining / 60))))"
        } else if presentationDetector?.isPresenting == true {
            badge = "PR"
        } else {
            badge = ""
        }
        button.title = badge
        button.image = statusImage(for: languageCode)
    }

    private func statusImage(for languageCode: String?) -> NSImage {
        let state: StatusBarIconState
        if isSecureTextField || isSecureInputGlobal {
            state = .secure
        } else if appState.isEnabled == false {
            state = .disabled
        } else if let code = languageCode {
            state = .language(code: code)
        } else {
            state = .fallback
        }
        return StatusBarIconRenderer.image(for: state)
    }

    static func languageBadge(_ code: String) -> String {
        let prefix = code.prefix(2).lowercased()
        return prefix.uppercased()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let toggleItem = NSMenuItem(
            title: String(localized: appState.isEnabled ? "statusitem.menu.disable" : "statusitem.menu.enable"),
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.identifier = .toggleEnabled
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let axItem = NSMenuItem(title: String(localized: "statusitem.menu.accessibility-not-granted"), action: nil, keyEquivalent: "")
        axItem.identifier = .accessibilityStatus
        axItem.isEnabled = false
        menu.addItem(axItem)

        let lastActionItem = NSMenuItem(title: String(localized: "statusitem.menu.last-action-empty"), action: nil, keyEquivalent: "")
        lastActionItem.identifier = .lastAction
        lastActionItem.isEnabled = false
        menu.addItem(lastActionItem)

        let snoozeItem = NSMenuItem(
            title: String(localized: "statusitem.menu.snooze"),
            action: #selector(toggleSnooze),
            keyEquivalent: ""
        )
        snoozeItem.target = self
        snoozeItem.identifier = .snooze
        menu.addItem(snoozeItem)

        let presentationItem = NSMenuItem(
            title: String(localized: "statusitem.menu.presentation-off"),
            action: nil,
            keyEquivalent: ""
        )
        presentationItem.identifier = .presentation
        presentationItem.isEnabled = false
        menu.addItem(presentationItem)

        let setupItem = NSMenuItem(
            title: String(localized: "statusitem.menu.open-setup"),
            action: #selector(openSetup),
            keyEquivalent: ""
        )
        setupItem.target = self
        setupItem.identifier = .openSetup
        menu.addItem(setupItem)

        menu.addItem(.separator())

        let recentItem = NSMenuItem(title: String(localized: "statusitem.menu.recents"), action: nil, keyEquivalent: "")
        recentItem.identifier = .recents
        let submenu = NSMenu()
        recentItem.submenu = submenu
        menu.addItem(recentItem)

        menu.addItem(.separator())

        let prefsItem = NSMenuItem(
            title: String(localized: "statusitem.menu.preferences"),
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        let helpItem = NSMenuItem(
            title: String(localized: "statusitem.menu.help"),
            action: #selector(openHelpWindow),
            keyEquivalent: "?"
        )
        helpItem.target = self
        menu.addItem(helpItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: String(localized: "statusitem.menu.quit"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func rebuildRecents(_ submenu: NSMenu) {
        submenu.removeAllItems()
        if recents.entries.isEmpty {
            let empty = NSMenuItem(title: String(localized: "statusitem.menu.no-recent-switches"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
            return
        }
        for entry in recents.entries.prefix(10) {
            let title = "\(entry.original) → \(entry.corrected)" + (entry.bundleName.map { "  ·  \($0)" } ?? "")
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            if let bundleID = entry.bundleID, !exclusions.contains(bundleID) {
                let sub = NSMenu()
                let format = String(localized: "statusitem.menu.add-to-exceptions")
                let add = NSMenuItem(
                    title: String(format: format, entry.bundleName ?? bundleID),
                    action: #selector(addBundleToExclusions(_:)),
                    keyEquivalent: ""
                )
                add.target = self
                add.representedObject = bundleID
                sub.addItem(add)
                item.submenu = sub
            }
            submenu.addItem(item)
        }
    }

    @objc private func toggleEnabled() {
        appState.isEnabled.toggle()
    }

    @objc private func toggleSnooze() {
        if appState.isSnoozed {
            appState.clearSnooze()
        } else {
            appState.startSnooze()
        }
        updateLayoutBadge(lastLanguageCode)
    }

    @objc private func openPreferences() {
        openSettings()
    }

    @objc private func openSetup() {
        openOnboarding()
    }

    @objc private func openHelpWindow() {
        openHelp()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func addBundleToExclusions(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        exclusions.add(id)
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        permission.refresh()

        if let toggleItem = menu.items.first(where: { $0.identifier == .toggleEnabled }) {
            toggleItem.title = String(localized: appState.isEnabled ? "statusitem.menu.disable" : "statusitem.menu.enable")
        }
        if let axItem = menu.items.first(where: { $0.identifier == .accessibilityStatus }) {
            axItem.title = String(localized: permission.isTrusted ? "statusitem.menu.accessibility-granted" : "statusitem.menu.accessibility-not-granted")
        }
        if let lastActionItem = menu.items.first(where: { $0.identifier == .lastAction }) {
            let lastActionFormat = String(localized: "statusitem.menu.last-action")
            lastActionItem.title = String(format: lastActionFormat, appState.lastActionDescription ?? "—")
        }
        if let snoozeItem = menu.items.first(where: { $0.identifier == .snooze }) {
            if let remaining = appState.activeSnoozeRemaining {
                let minutes = max(1, Int(ceil(remaining / 60)))
                let resumeFormat = String(localized: "statusitem.menu.resume-snooze")
                snoozeItem.title = String(format: resumeFormat, minutes)
            } else {
                let snoozeFormat = String(localized: "statusitem.menu.snooze")
                snoozeItem.title = String(format: snoozeFormat, appState.snoozeDuration.localizedTitle)
            }
            updateLayoutBadge(lastLanguageCode)
        }
        if let setupItem = menu.items.first(where: { $0.identifier == .openSetup }) {
            setupItem.isHidden = permission.isTrusted
        }
        if let presentationItem = menu.items.first(where: { $0.identifier == .presentation }) {
            let active = presentationDetector?.isPresenting == true
            presentationItem.title = active
                ? String(localized: "statusitem.menu.presentation-on")
                : String(localized: "statusitem.menu.presentation-off")
            updateLayoutBadge(lastLanguageCode)
        }
        if let recentItem = menu.items.first(where: { $0.identifier == .recents }),
           let submenu = recentItem.submenu {
            rebuildRecents(submenu)
        }
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let toggleEnabled = NSUserInterfaceItemIdentifier("toggleEnabled")
    static let accessibilityStatus = NSUserInterfaceItemIdentifier("accessibilityStatus")
    static let lastAction = NSUserInterfaceItemIdentifier("lastAction")
    static let snooze = NSUserInterfaceItemIdentifier("snooze")
    static let presentation = NSUserInterfaceItemIdentifier("presentation")
    static let openSetup = NSUserInterfaceItemIdentifier("openSetup")
    static let recents = NSUserInterfaceItemIdentifier("recents")
}
