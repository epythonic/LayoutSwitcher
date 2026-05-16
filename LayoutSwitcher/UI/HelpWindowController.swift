import AppKit
import SwiftUI

/// Owns and presents singleton Help window instance.
@MainActor
final class HelpWindowController: NSObject {
    /// Lazily created singleton help window.
    private var window: NSWindow?

    /// Opens help window or brings existing one to front.
    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: HelpView())
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "help.window.title")
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 820, height: 560))
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Closes help window while preserving controller instance.
    func close() {
        window?.close()
    }
}
