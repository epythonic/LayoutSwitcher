import AppKit
import SwiftUI

/// Owns first-run setup window lifecycle.
@MainActor
final class OnboardingWindowController: NSObject {
    /// Lazily created singleton onboarding window.
    private var window: NSWindow?
    /// Accessibility permission model displayed in onboarding.
    private let permission: AccessibilityPermission
    /// Input-source manager displayed in onboarding checks.
    private let inputSources: InputSourceManager
    /// Hotkey registry configured from onboarding.
    private let hotkeyRegistry: HotkeyRegistry

    /// Completion callback fired after successful onboarding.
    private let onFinish: () -> Void

    /// Creates a controller bound to shared onboarding dependencies.
    init(permission: AccessibilityPermission, inputSources: InputSourceManager, hotkeyRegistry: HotkeyRegistry, onFinish: @escaping () -> Void) {
        self.permission = permission
        self.inputSources = inputSources
        self.hotkeyRegistry = hotkeyRegistry
        self.onFinish = onFinish
    }

    /// Opens setup window or brings existing one to front.
    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = OnboardingView(
            permission: permission,
            inputSources: inputSources,
            hotkeyRegistry: hotkeyRegistry
        ) { [weak self] in
            self?.close()
            self?.onFinish()
        }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "onboarding.window.title")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Closes setup window.
    func close() {
        window?.close()
    }
}
