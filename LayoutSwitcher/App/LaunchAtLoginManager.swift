import Foundation
import os
#if canImport(ServiceManagement)
import ServiceManagement
#endif

/// Manages registration for automatic relaunch on macOS login using `SMAppService`.
///
/// On macOS 13+ the modern `SMAppService.mainApp` replaces the older `SMLoginItemSetEnabled` API.
@available(macOS 13.0, *)
@MainActor
struct LaunchAtLoginManager {
    /// ServiceManagement diagnostics logger.
    static let logger = Logger(subsystem: "GM.LayoutSwitcher", category: "LaunchAtLogin")

    /// Reads the current ServiceManagement registration status.
    private let statusProvider: @MainActor () -> SMAppService.Status
    /// Performs the production or test registration side effect.
    private let registerService: @MainActor () throws -> Void
    /// Performs the production or test unregistration side effect.
    private let unregisterService: @MainActor () throws -> Void

    /// Creates a launch-at-login manager with injectable ServiceManagement side effects.
    ///
    /// Tests replace all closures so no real login item is registered or removed.
    init(
        statusProvider: @escaping @MainActor () -> SMAppService.Status = {
            SMAppService.mainApp.status
        },
        registerService: @escaping @MainActor () throws -> Void = {
            try SMAppService.mainApp.register()
        },
        unregisterService: @escaping @MainActor () throws -> Void = {
            try SMAppService.mainApp.unregister()
        }
    ) {
        self.statusProvider = statusProvider
        self.registerService = registerService
        self.unregisterService = unregisterService
    }

    /// Current registration state. Read-only reflection of `SMAppService.status`.
    var isEnabled: Bool {
        statusProvider() == .enabled
    }

    /// Registers or unregisters the application for login-launch depending on `enabled`.
    ///
    /// Returns `true` on success, `false` when the operation fails (caller should show UI feedback).
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                let status = statusProvider()
                if status == .enabled {
                    return true
                }
                if status == .notFound {
                    Self.logger.error("Launch-at-login service not found — app may not be in /Applications")
                    return false
                }
                try registerService()
                Self.logger.info("Launch at login registered")
            } else {
                if statusProvider() == .notRegistered {
                    return true
                }
                try unregisterService()
                Self.logger.info("Launch at login unregistered")
            }
            return true
        } catch {
            Self.logger.error("Launch-at-login toggle failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
