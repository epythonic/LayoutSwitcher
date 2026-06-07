import Carbon.HIToolbox
import Foundation
import Observation
import os

/// Tracks current keyboard layout and provides utilities for querying/selecting sources.
@MainActor
@Observable
final class InputSourceManager {
    private static let logger = Logger(subsystem: "GM.LayoutSwitcher", category: "InputSource")

    /// Reads the currently selected keyboard input source.
    typealias CurrentInputSourceProvider = @MainActor () -> InputSource?
    /// Reads the system list of available keyboard layouts.
    typealias KeyboardLayoutsProvider = @MainActor () -> [InputSource]
    /// Selects a concrete keyboard input source and returns the Carbon status.
    typealias InputSourceSelector = @MainActor (InputSource) -> OSStatus
    /// Registers system layout-change observation and returns an opaque observer handle.
    typealias SystemChangeObserverRegistrar = @MainActor (InputSourceManager) -> UnsafeMutableRawPointer?
    /// Removes a previously registered layout-change observer.
    typealias SystemChangeObserverRemover = @MainActor (UnsafeMutableRawPointer) -> Void

    /// Captured snapshot of the currently selected keyboard layout.
    private(set) var current: InputSource?
    /// Callback fired when the selected layout actually changes.
    var onChange: ((InputSource?) -> Void)?
    /// Metadata-only callback fired when the selected layout changes.
    var onSnapshotChange: ((InputSourceSnapshot?) -> Void)?

    /// Opaque observer token returned by the distributed notification center.
    private var observerHandle: UnsafeMutableRawPointer?
    /// Injected current-source provider.
    private let currentInputSourceProvider: CurrentInputSourceProvider
    /// Injected keyboard-layout list provider.
    private let keyboardLayoutsProvider: KeyboardLayoutsProvider
    /// Injected input-source selector.
    private let selectInputSource: InputSourceSelector
    /// Injected system-change observer registrar.
    private let observeSystemChanges: SystemChangeObserverRegistrar
    /// Injected system-change observer remover.
    private let removeSystemChangeObserver: SystemChangeObserverRemover

    /// Creates the manager and loads the current layout immediately.
    ///
    /// All system interactions are injected so tests can avoid real TIS state.
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
