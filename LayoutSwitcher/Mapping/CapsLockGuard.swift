import CoreGraphics
import Foundation
import IOKit
import IOKit.hidsystem
import os

/// Captures Caps Lock state before retyping and restores it after, so synthesized
/// keystrokes are not silently uppercased by an active Caps Lock.
@MainActor
final class CapsLockGuard {
    private static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "CapsLock")

    typealias ReadCapsLockState = @MainActor () -> Bool
    typealias SetCapsLockState = @MainActor (Bool) -> Bool

    private var capturedState: Bool?
    private let readCapsLockState: ReadCapsLockState
    private let setCapsLockState: SetCapsLockState

    /// Creates a guard with explicit Caps Lock side effects.
    init(
        readCapsLockState: @escaping ReadCapsLockState,
        setCapsLockState: @escaping SetCapsLockState
    ) {
        self.readCapsLockState = readCapsLockState
        self.setCapsLockState = setCapsLockState
    }

    /// Creates the production guard backed by the current session Caps Lock state.
    static func live() -> CapsLockGuard {
        CapsLockGuard(
            readCapsLockState: Self.liveReadCapsLockState,
            setCapsLockState: Self.liveSetCapsLockState
        )
    }

    /// If Caps Lock is currently on, remember it and turn it off.
    /// No-op when already off.
    func captureAndDisable() {
        guard readCapsLockState() else { return }
        capturedState = true
        if !setCapsLockState(false) {
            capturedState = nil
        }
    }

    /// Restore the previously captured state, if any.
    func restore() {
        guard let state = capturedState else { return }
        capturedState = nil
        _ = setCapsLockState(state)
    }

    private static func liveReadCapsLockState() -> Bool {
        return CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
    }

    @discardableResult
    private static func liveSetCapsLockState(_ enabled: Bool) -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else {
            Self.logger.error("IOServiceGetMatchingService(kIOHIDSystemClass) returned 0")
            return false
        }
        defer { IOObjectRelease(service) }

        var ioConnect: io_connect_t = 0
        let openResult = IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &ioConnect)
        guard openResult == KERN_SUCCESS, ioConnect != 0 else {
            Self.logger.error("IOServiceOpen failed: \(openResult, privacy: .public)")
            return false
        }
        defer { IOServiceClose(ioConnect) }

        let setResult = IOHIDSetModifierLockState(ioConnect, Int32(kIOHIDCapsLockState), enabled)
        if setResult != KERN_SUCCESS {
            Self.logger.error("IOHIDSetModifierLockState failed: \(setResult, privacy: .public)")
            return false
        }
        return true
    }
}
