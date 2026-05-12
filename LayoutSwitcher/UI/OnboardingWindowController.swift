import AppKit
import SwiftUI

/// Owns first-run setup window lifecycle.
@MainActor
final class OnboardingWindowController: NSObject {
    private var window: NSWindow?
    private let permission: AccessibilityPermission
    private let inputSources: InputSourceManager
    private let hotkeyRegistry: HotkeyRegistry

    private let onFinish: () -> Void

    /// Creates controller bound to shared accessibility permission monitor.
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
