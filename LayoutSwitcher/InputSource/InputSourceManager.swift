import Carbon.HIToolbox
import Foundation
import Observation
import os

/// Tracks current keyboard layout and provides utilities for querying/selecting sources.
@MainActor
@Observable
final class InputSourceManager {
    private static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "InputSource")

    /// Captured snapshot of current selected keyboard layout.
    private(set) var current: InputSource?
    /// Callback fired when selected layout actually changes.
    var onChange: ((InputSource?) -> Void)?

    private var observerHandle: UnsafeMutableRawPointer?

    /// Creates manager and loads current layout immediately.
    init() {
        refresh()
    }

    /// Refreshes `current` from system TIS APIs.
    func refresh() {
        guard let ref = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            current = nil
            return
        }
        current = InputSource(ref)
    }

    /// Returns all keyboard-layout input sources known to the system.
    func keyboardLayouts() -> [InputSource] {
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceType: kTISTypeKeyboardLayout as Any
        ]
        guard let cfArray = TISCreateInputSourceList(filter as CFDictionary, true)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return cfArray.compactMap { InputSource($0) }
    }

    /// Returns enabled keyboard layouts that can be selected by user/app.
    func enabledLayouts() -> [InputSource] {
        keyboardLayouts().filter(\.isEnabled)
    }

    /// Attempts to select a specific input source as current.
    @discardableResult
    func select(_ source: InputSource) -> OSStatus {
        let status = source.selectAsCurrent()
        if status != noErr {
            Self.logger.error("TISSelectInputSource failed: \(status, privacy: .public) for \(source.id, privacy: .public)")
        }
        return status
    }

    /// Starts observing distributed notifications for system layout changes.
    func startObservingSystemChanges() {
        guard observerHandle == nil else { return }
        let center = CFNotificationCenterGetDistributedCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        observerHandle = observer

        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let manager = Unmanaged<InputSourceManager>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    manager.handleSystemChange()
                }
            },
            kTISNotifySelectedKeyboardInputSourceChanged as CFString,
            nil,
            .deliverImmediately
        )
    }

    /// Stops observing distributed notifications for system layout changes.
    func stopObservingSystemChanges() {
        guard let observer = observerHandle else { return }
        let center = CFNotificationCenterGetDistributedCenter()
        CFNotificationCenterRemoveObserver(
            center,
            observer,
            CFNotificationName(kTISNotifySelectedKeyboardInputSourceChanged),
            nil
        )
        observerHandle = nil
    }

    /// Handles external layout switch and emits `onChange` only for true transitions.
    private func handleSystemChange() {
        let previousID = current?.id
        refresh()
        if current?.id != previousID {
            Self.logger.info("Layout changed: \(self.current?.id ?? "?", privacy: .public)")
            onChange?(current)
        }
    }
}
