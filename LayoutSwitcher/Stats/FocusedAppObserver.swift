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
    var focusedFieldKind: FocusedFieldKind { get }
    var onChange: (@MainActor () -> Void)? { get set }
    func refreshSecureFieldState()
}

extension FocusedAppObserving {
    /// Default keeps existing stubs source-compatible; live observer overrides it.
    var focusedFieldKind: FocusedFieldKind { isSecureField ? .secure : .unknown }
}

/// Coarse classification of the focused text field, derived from AX role + subrole.
/// Used today only to harden secure-field detection and for diagnostics; the pipeline
/// continues to suppress corrections exclusively in `.secure` fields (no new UX risk).
enum FocusedFieldKind: String, Sendable, Equatable {
    /// Password / secure entry — corrections must never fire here.
    case secure
    /// Single-line search field.
    case search
    /// Ordinary editable text (text field or text area).
    case text
    /// No editable text element focused, or role could not be determined.
    case unknown

    /// Classifies a focused element from its AX role and optional subrole.
    /// Secure detection is widened: some apps expose a generic text role with an
    /// `AXSecureTextField` subrole rather than the dedicated secure role.
    static func classify(role: String?, subrole: String?) -> FocusedFieldKind {
        if role == "AXSecureTextField" || subrole == "AXSecureTextField" {
            return .secure
        }
        if subrole == "AXSearchField" {
            return .search
        }
        switch role {
        case "AXTextField", "AXTextArea", "AXComboBox":
            return .text
        default:
            return .unknown
        }
    }
}

/// Reads the focused AX role/subrole from the system to decide whether to look up the
/// focused element. Wrapped in a protocol so tests can mock without touching the AX subsystem.
@MainActor
protocol FocusedRoleProviding {
    /// Returns AX role string of currently focused UI element, if available.
    func focusedRole() -> String?
    /// Returns AX subrole string of currently focused UI element, if available.
    func focusedSubrole() -> String?
}

extension FocusedRoleProviding {
    /// Default lets existing role-only conformers (test stubs) compile unchanged.
    func focusedSubrole() -> String? { nil }
}

/// Live AX-based implementation of focused-role provider.
struct AXFocusedRoleProvider: FocusedRoleProviding {
    init() {}

    /// Reads focused AX element role from system-wide accessibility object.
    func focusedRole() -> String? {
        focusedAttribute(kAXRoleAttribute)
    }

    /// Reads focused AX element subrole from system-wide accessibility object.
    func focusedSubrole() -> String? {
        focusedAttribute(kAXSubroleAttribute)
    }

    /// Reads a single string attribute off the currently focused UI element.
    private func focusedAttribute(_ attribute: String) -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        guard status == .success, let element = focused else { return nil }
        guard let axElement = AXElementBridge.element(from: element) else { return nil }

        var value: CFTypeRef?
        let valueStatus = AXUIElementCopyAttributeValue(axElement, attribute as CFString, &value)
        guard valueStatus == .success else { return nil }
        return value as? String
    }
}

/// Metadata snapshot for the frontmost application.
struct WorkspaceAppSnapshot: Equatable, Sendable {
    let bundleID: String?
    let localizedName: String?

    nonisolated init(bundleID: String?, localizedName: String?) {
        self.bundleID = bundleID
        self.localizedName = localizedName
    }

    nonisolated init(app: NSRunningApplication) {
        self.bundleID = app.bundleIdentifier
        self.localizedName = app.localizedName
    }
}

typealias WorkspaceActivationHandler = @MainActor (WorkspaceAppSnapshot) -> Void
typealias WorkspaceActivationObserver = @MainActor (@escaping WorkspaceActivationHandler) -> NSObjectProtocol?

/// Observes frontmost app transitions and secure-input context for pipeline gating.
@MainActor
final class FocusedAppObserver: FocusedAppObserving {
    private static let logger = Logger(subsystem: "GM.LayoutSwitcher", category: "FocusedApp")

    private(set) var bundleID: String?
    private(set) var localizedName: String?
    private(set) var isSecureField: Bool = false
    private(set) var focusedFieldKind: FocusedFieldKind = .unknown

    var onChange: (@MainActor () -> Void)?

    private var observerToken: NSObjectProtocol?
    private var isStarted = false
    private let roleProvider: any FocusedRoleProviding
    private let currentAppSnapshotProvider: @MainActor () -> WorkspaceAppSnapshot?
    private let observeWorkspaceActivation: WorkspaceActivationObserver
    private let removeWorkspaceObserver: @MainActor (NSObjectProtocol) -> Void

    /// Creates observer backed by the provided workspace.
    convenience init(
        workspace: NSWorkspace,
        roleProvider: (any FocusedRoleProviding)? = nil
    ) {
        self.init(
            roleProvider: roleProvider,
            currentAppSnapshotProvider: {
                workspace.frontmostApplication.map(WorkspaceAppSnapshot.init)
            },
            observeWorkspaceActivation: { handler in
                let center = workspace.notificationCenter
                return center.addObserver(
                    forName: NSWorkspace.didActivateApplicationNotification,
                    object: nil,
                    queue: .main
                ) { notification in
                    guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                        return
                    }
                    let snapshot = WorkspaceAppSnapshot(app: app)
                    Task { @MainActor in
                        handler(snapshot)
                    }
                }
            },
            removeWorkspaceObserver: { token in
                workspace.notificationCenter.removeObserver(token)
            }
        )
    }

    /// Creates observer with injectable system-boundary closures for deterministic tests.
    init(
        roleProvider: (any FocusedRoleProviding)? = nil,
        currentAppSnapshotProvider: @escaping @MainActor () -> WorkspaceAppSnapshot?,
        observeWorkspaceActivation: @escaping WorkspaceActivationObserver,
        removeWorkspaceObserver: @escaping @MainActor (NSObjectProtocol) -> Void
    ) {
        self.roleProvider = roleProvider ?? AXFocusedRoleProvider()
        self.currentAppSnapshotProvider = currentAppSnapshotProvider
        self.observeWorkspaceActivation = observeWorkspaceActivation
        self.removeWorkspaceObserver = removeWorkspaceObserver
    }

    /// Starts NSWorkspace frontmost-app observation and publishes initial state.
    func start() {
        guard !isStarted else { return }
        isStarted = true

        observerToken = observeWorkspaceActivation { [weak self] snapshot in
            self?.update(with: snapshot)
        }

        if let snapshot = currentAppSnapshotProvider() {
            update(with: snapshot)
        }
    }

    /// Stops NSWorkspace observation.
    func stop() {
        if let token = observerToken {
            removeWorkspaceObserver(token)
            observerToken = nil
        }
        isStarted = false
    }

    /// Applies new focused app snapshot and notifies listeners.
    private func update(with snapshot: WorkspaceAppSnapshot) {
        bundleID = snapshot.bundleID
        localizedName = snapshot.localizedName
        refreshSecureFieldState()
        Self.logger.debug(
            "Focused app: \(self.localizedName ?? "?", privacy: .public) [\(self.bundleID ?? "?", privacy: .public)] secure=\(self.isSecureField, privacy: .public) field=\(self.focusedFieldKind.rawValue, privacy: .public)"
        )
        onChange?()
    }

    /// Recomputes focused-field classification from the current AX role + subrole.
    /// `isSecureField` is derived from the classification so password fields exposed
    /// via subrole (not just the dedicated secure role) are also detected.
    func refreshSecureFieldState() {
        let kind = FocusedFieldKind.classify(
            role: roleProvider.focusedRole(),
            subrole: roleProvider.focusedSubrole()
        )
        focusedFieldKind = kind
        isSecureField = (kind == .secure)
    }
}
