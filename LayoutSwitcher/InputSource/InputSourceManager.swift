import Carbon.HIToolbox
import Foundation
import Observation
import os

/// Tracks current keyboard layout and provides utilities for querying/selecting sources.
@MainActor
@Observable
final class InputSourceManager {
    private static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "InputSource")

    typealias CurrentInputSourceProvider = @MainActor () -> InputSource?
    typealias KeyboardLayoutsProvider = @MainActor () -> [InputSource]
    typealias InputSourceSelector = @MainActor (InputSource) -> OSStatus
    typealias SystemChangeObserverRegistrar = @MainActor (InputSourceManager) -> UnsafeMutableRawPointer?
    typealias SystemChangeObserverRemover = @MainActor (UnsafeMutableRawPointer) -> Void

    /// Captured snapshot of current selected keyboard layout.
    private(set) var current: InputSource?
    /// Callback fired when selected layout actually changes.
    var onChange: ((InputSource?) -> Void)?
    /// Metadata-only callback fired when selected layout changes.
    var onSnapshotChange: ((InputSourceSnapshot?) -> Void)?

    private var observerHandle: UnsafeMutableRawPointer?
    private let currentInputSourceProvider: CurrentInputSourceProvider
    private let keyboardLayoutsProvider: KeyboardLayoutsProvider
    private let selectInputSource: InputSourceSelector
    private let observeSystemChanges: SystemChangeObserverRegistrar
    private let removeSystemChangeObserver: SystemChangeObserverRemover

    /// Creates manager and loads current layout immediately.
    init(
        currentInputSourceProvider: @escaping CurrentInputSourceProvider = InputSourceManager.currentInputSource,
        keyboardLayoutsProvider: @escaping KeyboardLayoutsProvider = InputSourceManager.systemKeyboardLayouts,
        selectInputSource: @escaping InputSourceSelector = { source in
            source.selectAsCurrent()
        },
        observeSystemChanges: @escaping SystemChangeObserverRegistrar = InputSourceManager.registerSystemChangeObserver,
        removeSystemChangeObserver: @escaping SystemChangeObserverRemover = InputSourceManager.unregisterSystemChangeObserver
    ) {
        self.currentInputSourceProvider = currentInputSourceProvider
        self.keyboardLayoutsProvider = keyboardLayoutsProvider
        self.selectInputSource = selectInputSource
        self.observeSystemChanges = observeSystemChanges
        self.removeSystemChangeObserver = removeSystemChangeObserver
        refresh()
    }

    /// Refreshes `current` from system TIS APIs.
    func refresh() {
        current = currentInputSourceProvider()
    }

    /// Returns all keyboard-layout input sources known to the system.
    func keyboardLayouts() -> [InputSource] {
        keyboardLayoutsProvider()
    }

    /// Returns enabled keyboard layouts that can be selected by user/app.
    func enabledLayouts() -> [InputSource] {
        keyboardLayouts().filter(\.isEnabled)
    }

    /// Attempts to select a specific input source as current.
    @discardableResult
    func select(_ source: InputSource) -> OSStatus {
        let status = selectInputSource(source)
        if status != noErr {
            Self.logger.error("TISSelectInputSource failed: \(status, privacy: .public) for \(source.id, privacy: .public)")
        }
        return status
    }

    /// Starts observing distributed notifications for system layout changes.
    func startObservingSystemChanges() {
        guard observerHandle == nil else { return }
        observerHandle = observeSystemChanges(self)
    }

    /// Stops observing distributed notifications for system layout changes.
    func stopObservingSystemChanges() {
        guard let observer = observerHandle else { return }
        removeSystemChangeObserver(observer)
        observerHandle = nil
    }

    /// Handles external layout switch and emits `onChange` only for true transitions.
    private func handleSystemChange() {
        let previousID = current?.id
        refresh()
        if current?.id != previousID {
            Self.logger.info("Layout changed: \(self.current?.id ?? "?", privacy: .public)")
            onChange?(current)
            onSnapshotChange?(current?.snapshot)
        }
    }

    /// Reads the current selected keyboard layout from system TIS APIs.
    private static func currentInputSource() -> InputSource? {
        guard let ref = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return InputSource(ref)
    }

    /// Reads all keyboard-layout input sources from system TIS APIs.
    private static func systemKeyboardLayouts() -> [InputSource] {
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceType: kTISTypeKeyboardLayout as Any
        ]
        guard let cfArray = TISCreateInputSourceList(filter as CFDictionary, true)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return cfArray.compactMap { InputSource($0) }
    }

    /// Registers the system distributed notification observer for layout changes.
    private static func registerSystemChangeObserver(for manager: InputSourceManager) -> UnsafeMutableRawPointer? {
        let center = CFNotificationCenterGetDistributedCenter()
        let observer = Unmanaged.passUnretained(manager).toOpaque()

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
        return observer
    }

    /// Removes the system distributed notification observer for layout changes.
    private static func unregisterSystemChangeObserver(_ observer: UnsafeMutableRawPointer) {
        let center = CFNotificationCenterGetDistributedCenter()
        CFNotificationCenterRemoveObserver(
            center,
            observer,
            CFNotificationName(kTISNotifySelectedKeyboardInputSourceChanged),
            nil
        )
    }
}
