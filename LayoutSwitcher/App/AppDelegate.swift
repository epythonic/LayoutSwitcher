import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "AppDelegate")

    let appState = AppState()
    let permission = AccessibilityPermission()
    let eventTap = KeyboardEventTap()
    let wordBuffer = WordBuffer()
    let focusedApp = FocusedAppObserver()
    let inputSources = InputSourceManager()
    let exclusions = ExclusionList()
    let perAppLayouts = PerAppLayoutPreferences()
    let stats = UsageStats()
    let recents = RecentSwitches()
    let presentationDetector = PresentationModeDetector()
    let learningCache = LearningCache()
    let launchAtLoginManager = LaunchAtLoginManager()
    let notificationManager = NotificationManager()
    let secureInputObserver = SecureInputObserver()
    private let onboardingCompletionStore: OnboardingCompletionStore
    let userEnglish = UserDictionary(language: .en)
    let userRussian = UserDictionary(language: .ru)
    let userUkrainian = UserDictionary(language: .uk)
    let userRomanian = UserDictionary(language: .ro)
    private(set) lazy var detector: LayoutDetector = LayoutDetector.defaultMultilingual(
        userEnglish: userEnglish,
        userRussian: userRussian,
        userUkrainian: userUkrainian,
        userRomanian: userRomanian
    )
    private(set) lazy var retyper: Retyper = Retyper(mapping: detector.mapping, inputSources: inputSources)
    private(set) lazy var smartPaste: SmartPaste = SmartPaste(inputSources: inputSources)
    private(set) lazy var pipeline = TypingPipeline(
        buffer: wordBuffer,
        focused: focusedApp,
        detector: detector,
        retyper: retyper,
        inputSources: inputSources,
        learningCache: learningCache,
        presentationDetector: presentationDetector,
        notificationManager: notificationManager,
        exclusions: exclusions,
        stats: stats,
        recents: recents,
        perAppLayouts: perAppLayouts
    )
    private(set) lazy var hotkeyRegistry = HotkeyRegistry()
    let carbonHotkeyManager = CarbonHotkeyManager()
    private(set) lazy var hotkeyCoordinator = HotkeyCoordinator(
        buffer: wordBuffer,
        mapping: detector.mapping,
        retyper: retyper,
        inputSources: inputSources,
        stats: stats,
        recents: recents,
        appState: appState,
        smartPaste: smartPaste,
        learningCache: learningCache,
        currentBundleIDProvider: { [weak focusedApp] in focusedApp?.bundleID }
    )

    var statusItemController: StatusItemController?
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private let helpWindowController = HelpWindowController()

    override init() {
        self.onboardingCompletionStore = OnboardingCompletionStore()
        super.init()
    }

    init(onboardingCompletionStore: OnboardingCompletionStore) {
        self.onboardingCompletionStore = onboardingCompletionStore
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        appState.isAccessibilityGranted = permission.isTrusted
        pipeline.appState = appState

        focusedApp.start()
        _ = pipeline

        appState.currentLayoutID = inputSources.currentSnapshot?.localizedName
        inputSources.onSnapshotChange = { [weak self] snapshot in
            self?.appState.currentLayoutID = snapshot?.localizedName
            self?.statusItemController?.updateLayoutBadge(snapshot?.primaryLanguage)
        }
        inputSources.startObservingSystemChanges()

        pipeline.hotkeyCoordinator = hotkeyCoordinator
        hotkeyCoordinator.typingPipeline = pipeline
        hotkeyCoordinator.forceRetypeHandler = { [weak pipeline] in pipeline?.forceRetypeLastWord() }

        notificationManager.registerCategories()
        notificationManager.requestAuthorization()
        notificationManager.onUndoRequested = { [weak self] in
            self?.hotkeyCoordinator.handle(.undoLastAutoSwitch)
        }
        hotkeyCoordinator.onSnoozeChanged = { [weak self] in
            guard let self else { return }
            self.statusItemController?.updateLayoutBadge(self.inputSources.currentSnapshot?.primaryLanguage)
        }
        hotkeyRegistry.onAction = { [weak self] action in
            self?.hotkeyCoordinator.handle(action)
        }

        carbonHotkeyManager.onAction = { [weak self] action in
            self?.hotkeyRegistry.onAction?(action)
        }
        carbonHotkeyManager.install()
        carbonHotkeyManager.register(hotkeyRegistry.bindings)
        hotkeyRegistry.onBindingsChanged = { [weak self] in
            guard let self else { return }
            self.carbonHotkeyManager.register(self.hotkeyRegistry.bindings)
        }

        // Carbon dispatches hotkey actions; event tap only suppresses the matching
        // keyDown so the pipeline doesn't classify it as text input.
        eventTap.hotkeyHandler = { [weak self] event in
            self?.hotkeyRegistry.match(event) != nil
        }
        eventTap.onKeyEvent = { [weak self] event in
            guard let self else { return }
            self.pipeline.handle(event)
        }

        permission.onTrustGranted = { [weak self] in
            guard let self else { return }
            self.appState.isAccessibilityGranted = true
            self.eventTap.start()
            Self.logger.info("Accessibility granted — event tap installed")
        }

        // Sync UserDefaults state with actual SMAppService status (user may have toggled in System Settings).
        let systemLaunchAtLoginEnabled = launchAtLoginManager.isEnabled
        if appState.launchAtLogin != systemLaunchAtLoginEnabled {
            if systemLaunchAtLoginEnabled {
                Self.logger.info("Launch at login was enabled externally, synced state to true")
            } else {
                Self.logger.info("Launch at login was disabled externally, synced state to false")
            }
            appState.launchAtLogin = systemLaunchAtLoginEnabled
        }

        let helpController = self.helpWindowController
        let settingsController = SettingsWindowController(
            appState: appState,
            exclusions: exclusions,
            stats: stats,
            userEnglish: userEnglish,
            userRussian: userRussian,
            userUkrainian: userUkrainian,
            userRomanian: userRomanian,
            inputSources: inputSources,
            hotkeys: hotkeyRegistry,
            perAppLayouts: perAppLayouts,
            recents: recents,
            learningCache: learningCache,
            launchAtLoginManager: launchAtLoginManager,
            openHelp: { [weak helpController] in helpController?.show() }
        )
        self.settingsWindowController = settingsController

        let onboardingController = OnboardingWindowController(
            permission: permission,
            inputSources: inputSources,
            hotkeyRegistry: hotkeyRegistry,
            onFinish: { [weak self] in
                guard let self else { return }
                self.onboardingCompletionStore.markCompleted()
                if self.permission.isTrusted {
                    self.eventTap.start()
                    Self.logger.info("Onboarding finished — event tap started")
                }
            }
        )
        self.onboardingWindowController = onboardingController

        self.statusItemController = StatusItemController(
            appState: appState,
            permission: permission,
            recents: recents,
            exclusions: exclusions,
            presentationDetector: presentationDetector,
            openSettings: { [weak settingsController] in
                settingsController?.show()
            },
            openOnboarding: { [weak onboardingController] in
                onboardingController?.show()
            },
            openHelp: { [weak helpController] in
                helpController?.show()
            }
        )
        pipeline.focusContextDidChange = { [weak self] in
            guard let self else { return }
            statusItemController?.updateSecureTextFieldState(focusedApp.isSecureField)
            statusItemController?.updateLayoutBadge(inputSources.currentSnapshot?.primaryLanguage)
        }
        statusItemController?.updateSecureTextFieldState(focusedApp.isSecureField)
        statusItemController?.updateLayoutBadge(inputSources.currentSnapshot?.primaryLanguage)

        secureInputObserver.onChange = { [weak self] isSecure in
            self?.statusItemController?.updateGlobalSecureInputState(isSecure)
        }
        secureInputObserver.start()
        statusItemController?.updateGlobalSecureInputState(secureInputObserver.isSecureInputEnabled)

        let hasCompletedOnboarding = onboardingCompletionStore.isCompleted
        if !hasCompletedOnboarding {
            if !permission.isTrusted {
                permission.startPolling()
            }
            onboardingController.show()
        } else if permission.isTrusted {
            eventTap.start()
        } else {
            permission.startPolling()
            onboardingController.show()
        }

        Self.logger.info("LayoutSwitcher started (AX trusted: \(self.permission.isTrusted, privacy: .public), onboarding completed: \(hasCompletedOnboarding, privacy: .public)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTap.stop()
        focusedApp.stop()
        secureInputObserver.stop()
        carbonHotkeyManager.uninstall()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
