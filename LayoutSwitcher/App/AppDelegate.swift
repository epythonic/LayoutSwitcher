import AppKit
import UserNotifications
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let logger = Logger(subsystem: "GM.LayoutSwitcher", category: "AppDelegate")
    private static let xctestConfigurationEnvironmentKey = "XCTestConfigurationFilePath"
    private static let uiTestingEnvironmentKey = "LAYOUTSWITCHER_UI_TESTING"
    private static let uiTestingOpenSettingsEnvironmentKey = "LAYOUTSWITCHER_UI_TESTING_OPEN_SETTINGS"

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment[Self.xctestConfigurationEnvironmentKey] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    private static var isRunningUITests: Bool {
        ProcessInfo.processInfo.environment[Self.uiTestingEnvironmentKey] == "1"
    }

    let appState = AppState(defaults: .standard, now: Date.init)
    let permission = AccessibilityPermission(workspace: .shared)
    let eventTap = KeyboardEventTap()
    let wordBuffer = WordBuffer(now: Date.init)
    let focusedApp = FocusedAppObserver(workspace: .shared)
    let inputSources = InputSourceManager()
    /// Retains the wake-from-sleep observer so input sources are reconciled after wake.
    private var wakeObserver: (any NSObjectProtocol)?
    let exclusions = ExclusionList(defaults: .standard, workspace: .shared)
    let perAppLayouts = PerAppLayoutPreferences(
        defaults: .standard,
        appNameProvider: { ExclusionList.localizedName(for: $0, workspace: .shared) }
    )
    let stats = UsageStats(defaults: .standard, now: Date.init)
    let recents = RecentSwitches(defaults: .standard, makeEntryID: UUID.init)
    let presentationDetector = PresentationModeDetector(workspace: .shared)
    let learningCache = LearningCache(defaults: .standard, now: Date.init, makeEntryID: UUID.init)
    let launchAtLoginManager = LaunchAtLoginManager()
    let notificationManager = NotificationManager(
        notificationCenter: .current(),
        makeNotificationID: { UUID().uuidString },
        notificationSound: .default
    )
    let secureInputObserver = SecureInputObserver()
    private let onboardingCompletionStore: OnboardingCompletionStore
    let userEnglish = UserDictionary(language: .en, fileManager: .default)
    let userRussian = UserDictionary(language: .ru, fileManager: .default)
    let userUkrainian = UserDictionary(language: .uk, fileManager: .default)
    let userRomanian = UserDictionary(language: .ro, fileManager: .default)
    private(set) lazy var detector: LayoutDetector = LayoutDetector.defaultMultilingual(
        userEnglish: userEnglish,
        userRussian: userRussian,
        userUkrainian: userUkrainian,
        userRomanian: userRomanian,
        systemSpellChecker: NSSpellChecker.shared,
        thresholds: .default
    )
    private(set) lazy var retyper: Retyper = makeRetyper()
    private(set) lazy var smartPaste: SmartPaste = makeSmartPaste()
    private(set) lazy var pipeline = makePipeline()
    private(set) lazy var hotkeyRegistry = HotkeyRegistry(defaults: .standard)
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
        currentBundleIDProvider: { [weak focusedApp] in focusedApp?.bundleID },
        bundleNameProvider: { ExclusionList.localizedName(for: $0, workspace: .shared) },
        now: Date.init
    )

    var statusItemController: StatusItemController?
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private let helpWindowController = HelpWindowController()

    override init() {
        self.onboardingCompletionStore = OnboardingCompletionStore(defaults: .standard)
        super.init()
    }

    init(onboardingCompletionStore: OnboardingCompletionStore) {
        self.onboardingCompletionStore = onboardingCompletionStore
        super.init()
    }

    private func makeSmartPaste() -> SmartPaste {
        SmartPaste(
            inputSources: inputSources,
            pasteboardRead: {
                NSPasteboard.general.string(forType: .string)
            },
            postKeyEvent: { keyCode, flags in
                SmartPaste.postKey(keyCode: keyCode, flags: flags)
            },
            sleep: { nanoseconds in
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
        )
    }

    private func makeRetyper() -> Retyper {
        Retyper(
            mapping: detector.mapping,
            enabledLayoutsProvider: { [inputSources] in
                inputSources.enabledLayouts().map { RetypeInputSource($0) }
            },
            currentLayoutIDProvider: { [inputSources] in
                inputSources.current?.id
            },
            refreshCurrentLayout: { [inputSources] in
                inputSources.refresh()
            },
            selectLayout: { [inputSources] layout in
                guard let source = layout.source else { return OSStatus(paramErr) }
                return inputSources.select(source)
            },
            sleep: { nanoseconds in
                try? await Task.sleep(nanoseconds: nanoseconds)
            },
            postKeyEvent: { keyCode, flags in
                Retyper.postKey(keyCode: keyCode, flags: flags)
            },
            postUnicodeEvent: { text in
                Retyper.postUnicode(text)
            },
            capsLockGuard: CapsLockGuard.live()
        )
    }

    private func makePipeline() -> TypingPipeline {
        TypingPipeline(
            buffer: wordBuffer,
            focused: focusedApp,
            detector: detector,
            retyper: retyper,
            inputSources: inputSources,
            learningCache: learningCache,
            soundFeedback: SoundFeedbackPlayer.live(),
            visualFeedback: VisualFeedbackPlayer { [weak self] kind in
                self?.statusItemController?.flashCorrection(kind)
            },
            presentationDetector: presentationDetector,
            notificationManager: notificationManager,
            exclusions: exclusions,
            stats: stats,
            recents: recents,
            perAppLayouts: perAppLayouts,
            tunables: .default,
            bundleNameProvider: { ExclusionList.localizedName(for: $0, workspace: .shared) },
            sleepBeforeSequenceFlush: { duration in
                try? await Task.sleep(for: duration)
            },
            now: Date.init
        )
    }

    private func makeSettingsWindowController() -> SettingsWindowController {
        let helpController = self.helpWindowController
        return SettingsWindowController(
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
    }

    private func launchForUITests() {
        NSApp.setActivationPolicy(.regular)
        appState.isAccessibilityGranted = true
        settingsWindowController = makeSettingsWindowController()

        if ProcessInfo.processInfo.environment[Self.uiTestingOpenSettingsEnvironmentKey] == "1" {
            settingsWindowController?.show()
        }

        Self.logger.info("LayoutSwitcher UI test mode started")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Self.isRunningUITests {
            launchForUITests()
            return
        }

        guard !Self.isRunningUnitTests else {
            Self.logger.info("XCTest launch detected; skipping live app startup side effects")
            return
        }

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
        // After wake-from-sleep the cached current source can be stale; reconcile it.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.inputSources.reconcileCurrentInputSource()
            }
        }

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
        let settingsController = makeSettingsWindowController()
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
