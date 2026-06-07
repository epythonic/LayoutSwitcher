import AppKit
@preconcurrency import ApplicationServices
import Observation
import os

/// Invalidation handle for Accessibility trust polling.
@MainActor
protocol AccessibilityPermissionPolling: AnyObject {
    /// Stops the active polling resource.
    func invalidate()
}

extension Timer: AccessibilityPermissionPolling {}

/// Observes and prompts Accessibility trust required for global key event taps.
@MainActor
@Observable
final class AccessibilityPermission {
    private static let logger = Logger(subsystem: "GM.LayoutSwitcher", category: "Accessibility")

    typealias TrustStatusProvider = @MainActor () -> Bool
    typealias TrustPromptRequester = @MainActor () -> Void
    typealias SystemSettingsOpener = @MainActor (URL) -> Void
    typealias PollingTimerFactory = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> any AccessibilityPermissionPolling

    private let pollingInterval: TimeInterval
    private let trustStatusProvider: TrustStatusProvider
    private let trustPromptRequester: TrustPromptRequester
    private let systemSettingsOpener: SystemSettingsOpener
    private let pollingTimerFactory: PollingTimerFactory

    private(set) var isTrusted: Bool
    private var pollTimer: (any AccessibilityPermissionPolling)?
    var onTrustGranted: (@MainActor () -> Void)?

    /// Creates permission observer backed by system Accessibility APIs and the provided workspace.
    convenience init(
        pollingInterval: TimeInterval = 1.0,
        workspace: NSWorkspace
    ) {
        self.init(
            pollingInterval: pollingInterval,
            trustStatusProvider: {
                AXIsProcessTrusted()
            },
            trustPromptRequester: {
                let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                let options: [String: Bool] = [key: true]
                _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            },
            systemSettingsOpener: { url in
                _ = workspace.open(url)
            },
            pollingTimerFactory: { interval, tick in
                let timer = Timer(timeInterval: interval, repeats: true) { _ in
                    Task { @MainActor in
                        tick()
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                return timer
            }
        )
    }

    /// Creates permission observer with injectable system-boundary closures for deterministic tests.
    init(
        pollingInterval: TimeInterval = 1.0,
        trustStatusProvider: @escaping TrustStatusProvider,
        trustPromptRequester: @escaping TrustPromptRequester,
        systemSettingsOpener: @escaping SystemSettingsOpener,
        pollingTimerFactory: @escaping PollingTimerFactory
    ) {
        self.pollingInterval = pollingInterval
        self.trustStatusProvider = trustStatusProvider
        self.trustPromptRequester = trustPromptRequester
        self.systemSettingsOpener = systemSettingsOpener
        self.pollingTimerFactory = pollingTimerFactory
        self.isTrusted = trustStatusProvider()
    }

    /// Snapshot trust state without instantiating observable object.
    static var current: Bool { AXIsProcessTrusted() }

    /// Re-reads trust status and emits callback when permission is newly granted.
    func refresh() {
        let trusted = trustStatusProvider()
        if trusted != isTrusted {
            Self.logger.info("Accessibility trust changed: \(trusted, privacy: .public)")
            isTrusted = trusted
            if trusted { onTrustGranted?() }
        }
    }

    /// Triggers system prompt for Accessibility permission.
    func promptForTrust() {
        trustPromptRequester()
        refresh()
    }

    /// Opens System Settings privacy pane for Accessibility controls.
    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        systemSettingsOpener(url)
    }

    /// Starts lightweight polling loop to detect trust changes while onboarding is visible.
    func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = pollingTimerFactory(pollingInterval) { [weak self] in
            self?.refresh()
        }
    }

    /// Stops trust polling loop.
    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
