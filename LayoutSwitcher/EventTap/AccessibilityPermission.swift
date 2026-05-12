import AppKit
@preconcurrency import ApplicationServices
import Observation
import os

/// Observes and prompts Accessibility trust required for global key event taps.
@MainActor
@Observable
final class AccessibilityPermission {
    private static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "Accessibility")

    private(set) var isTrusted: Bool = AXIsProcessTrusted()
    private var pollTimer: Timer?
    var onTrustGranted: (() -> Void)?

    /// Snapshot trust state without instantiating observable object.
    static var current: Bool { AXIsProcessTrusted() }

    /// Re-reads trust status and emits callback when permission is newly granted.
    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted {
            Self.logger.info("Accessibility trust changed: \(trusted, privacy: .public)")
            isTrusted = trusted
            if trusted { onTrustGranted?() }
        }
    }

    /// Triggers system prompt for Accessibility permission.
    func promptForTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: [String: Bool] = [key: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        refresh()
    }

    /// Opens System Settings privacy pane for Accessibility controls.
    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Starts lightweight polling loop to detect trust changes while onboarding is visible.
    func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    /// Stops trust polling loop.
    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
