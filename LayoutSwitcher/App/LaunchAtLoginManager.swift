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
final class LaunchAtLoginManager {
    static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "LaunchAtLogin")

    private static let serviceName = "GIH.LayoutSwitcher"

    /// Current registration state. Read-only reflection of `SMAppService.status`.
    var isEnabled: Bool {
        let service = SMAppService.mainApp
        return service.status == .enabled
    }

    /// Registers or unregisters the application for login-launch depending on `enabled`.
    ///
    /// Returns `true` on success, `false` when the operation fails (caller should show UI feedback).
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status == .notFound {
                    Self.logger.error("Launch-at-login service not found — app may not be in /Applications")
                    return false
                }
                try service.register()
                Self.logger.info("Launch at login registered")
            } else {
                try service.unregister()
                Self.logger.info("Launch at login unregistered")
            }
            return true
        } catch {
            Self.logger.error("Launch-at-login toggle failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
