import Carbon.HIToolbox
import Foundation

/// Read/write contract over keyboard input sources consumed by pipeline,
/// retyper, hot-key actions and smart paste. Decouples those components from
/// the Carbon-backed `InputSourceManager` so tests can wire in deterministic
/// fakes (no real `TISInputSource`, no global system layout side effects).
@MainActor
protocol InputSourceManaging: AnyObject {
    /// Currently selected keyboard layout, or nil if none could be resolved.
    var current: InputSource? { get }

    /// Forces a re-read of the system's current layout into `current`.
    func refresh()

    /// All keyboard-layout input sources known to the system (enabled or not).
    func keyboardLayouts() -> [InputSource]

    /// Enabled, user-selectable keyboard layouts.
    func enabledLayouts() -> [InputSource]

    /// Requests `source` to become active. Returns `noErr` on success.
    @discardableResult
    func select(_ source: InputSource) -> OSStatus
}

extension InputSourceManager: InputSourceManaging {}

extension InputSourceManaging {
    /// Current layout metadata without the live Carbon input-source reference.
    var currentSnapshot: InputSourceSnapshot? {
        current?.snapshot
    }

    /// All keyboard-layout metadata snapshots known to the system.
    func keyboardLayoutSnapshots() -> [InputSourceSnapshot] {
        keyboardLayouts().map(\.snapshot)
    }

    /// Enabled keyboard-layout metadata snapshots safe for UI/read-only use.
    func enabledLayoutSnapshots() -> [InputSourceSnapshot] {
        enabledLayouts().map(\.snapshot)
    }

    /// Finds enabled keyboard-layout metadata by stable input-source identifier.
    func enabledLayoutSnapshot(id: String) -> InputSourceSnapshot? {
        enabledLayoutSnapshots().first { $0.id == id }
    }
}
