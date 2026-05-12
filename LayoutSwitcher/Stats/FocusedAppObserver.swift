import AppKit
import ApplicationServices
import os

/// Source of focused-app context that `TypingPipeline` consumes.
/// Decoupled from the concrete AX-backed observer so tests can supply a stub.
@MainActor
protocol FocusedAppObserving: AnyObject {
    var bundleID: String? { get }
    var localizedName: String? { get }
    var isSecureField: Bool { get }
    var onChange: (() -> Void)? { get set }
    func refreshSecureFieldState()
}

/// Reads the focused AX role from the system to decide whether to look up the focused
/// element. Wrapped in a protocol so tests can mock without touching the AX subsystem.
@MainActor
protocol FocusedRoleProviding {
    /// Returns AX role string of currently focused UI element, if available.
    func focusedRole() -> String?
}

/// Live AX-based implementation of focused-role provider.
struct AXFocusedRoleProvider: FocusedRoleProviding {
    init() {}

    /// Reads focused AX element role from system-wide accessibility object.
    func focusedRole() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        guard status == .success, let element = focused else { return nil }
        guard CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        let axElement = unsafeBitCast(element, to: AXUIElement.self)

        var role: CFTypeRef?
        let roleStatus = AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &role)
        guard roleStatus == .success else { return nil }
        return role as? String
    }
}

/// Observes frontmost app transitions and secure-input context for pipeline gating.
@MainActor
final class FocusedAppObserver: FocusedAppObserving {
    private static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "FocusedApp")

    private(set) var bundleID: String?
    private(set) var localizedName: String?
    private(set) var isSecureField: Bool = false

    var onChange: (() -> Void)?

    private var observerToken: NSObjectProtocol?
    private let roleProvider: any FocusedRoleProviding

    /// Creates observer with injectable AX role provider (used by tests).
    init(roleProvider: (any FocusedRoleProviding)? = nil) {
        self.roleProvider = roleProvider ?? AXFocusedRoleProvider()
    }

    /// Starts NSWorkspace frontmost-app observation and publishes initial state.
    func start() {
        let center = NSWorkspace.shared.notificationCenter
        observerToken = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                self?.update(with: app)
            }
        }

        if let app = NSWorkspace.shared.frontmostApplication {
            update(with: app)
        }
    }

    /// Stops NSWorkspace observation.
    func stop() {
        if let token = observerToken {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            observerToken = nil
        }
    }

    /// Applies new focused app snapshot and notifies listeners.
    private func update(with app: NSRunningApplication) {
        bundleID = app.bundleIdentifier
        localizedName = app.localizedName
        refreshSecureFieldState()
        Self.logger.debug(
            "Focused app: \(self.localizedName ?? "?", privacy: .public) [\(self.bundleID ?? "?", privacy: .public)] secure=\(self.isSecureField, privacy: .public)"
        )
        onChange?()
    }

    /// Recomputes secure-field flag from current focused AX element role.
    func refreshSecureFieldState() {
        let role = roleProvider.focusedRole()
        isSecureField = (role == "AXSecureTextField")
    }
}
