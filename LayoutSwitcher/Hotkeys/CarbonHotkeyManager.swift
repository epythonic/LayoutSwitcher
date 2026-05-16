import AppKit
import Carbon.HIToolbox
import Foundation
import os

/// Registers user hotkeys with the Carbon Event Manager.
///
/// Unlike CGEventTap matching, Carbon hotkeys keep working when the tap is
/// disabled by `tapDisabledByTimeout` / `tapDisabledByUserInput` and do not
/// require Accessibility permission to register.
@MainActor
final class CarbonHotkeyManager {
    private static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "CarbonHotkey")
    /// FourCharCode 'LSWT' identifier used for all hotkey IDs from this app.
    private static let signature: OSType = 0x4C53_5754

    /// Installed Carbon event handler reference, if active.
    private var handlerRef: EventHandlerRef?
    /// Registered Carbon hotkey references keyed by app-local hotkey ID.
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    /// App action lookup keyed by app-local hotkey ID.
    private var actionByID: [UInt32: HotkeyAction] = [:]
    /// Monotonic app-local hotkey ID generator.
    private var nextID: UInt32 = 1

    /// Callback invoked when Carbon reports a registered hotkey press.
    var onAction: ((HotkeyAction) -> Void)?

    /// Creates an empty manager; call `install()` before registering bindings.
    init() {}

    /// Install Carbon event handler that dispatches `kEventHotKeyPressed`.
    /// Idempotent.
    func install() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        var ref: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            CarbonHotkeyManager.handlerCallback,
            1,
            &spec,
            userData,
            &ref
        )
        guard status == noErr else {
            Self.logger.error("InstallEventHandler failed: \(status, privacy: .public)")
            return
        }
        handlerRef = ref
        Self.logger.info("Carbon hotkey handler installed")
    }

    /// Remove Carbon event handler and unregister all hotkeys.
    func uninstall() {
        unregisterAll()
        if let ref = handlerRef {
            RemoveEventHandler(ref)
            handlerRef = nil
        }
    }

    /// Replace currently registered hotkeys with the given bindings map.
    func register(_ bindings: [HotkeyDefinition: HotkeyAction]) {
        unregisterAll()
        for (definition, action) in bindings {
            registerOne(definition: definition, action: action)
        }
    }

    /// Registers one Carbon hotkey and stores its action mapping.
    private func registerOne(definition: HotkeyDefinition, action: HotkeyAction) {
        let id = nextID
        nextID &+= 1
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(definition.keyCode),
            carbonModifiers(definition.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            Self.logger.error(
                "RegisterEventHotKey failed for \(action.persistenceKey, privacy: .public): \(status, privacy: .public)"
            )
            return
        }
        hotKeyRefs[id] = ref
        actionByID[id] = action
    }

    /// Unregisters all Carbon hotkeys currently owned by this manager.
    private func unregisterAll() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        actionByID.removeAll()
    }

    /// Dispatches a Carbon hotkey ID to the configured app action callback.
    fileprivate func dispatch(id: UInt32) {
        guard let action = actionByID[id] else { return }
        onAction?(action)
    }

    /// Converts app-level modifier flags to Carbon modifier flags.
    private func carbonModifiers(_ mask: HotkeyDefinition.ModifierMask) -> UInt32 {
        var result: UInt32 = 0
        if mask.contains(.command) { result |= UInt32(cmdKey) }
        if mask.contains(.shift)   { result |= UInt32(shiftKey) }
        if mask.contains(.option)  { result |= UInt32(optionKey) }
        if mask.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    /// Carbon callback that extracts the hotkey ID and hops back to the main actor.
    private static let handlerCallback: EventHandlerUPP = { _, eventOpt, userDataOpt in
        guard let event = eventOpt, let userDataOpt else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == CarbonHotkeyManager.signature else {
            return status == noErr ? OSStatus(eventNotHandledErr) : status
        }
        let manager = Unmanaged<CarbonHotkeyManager>.fromOpaque(userDataOpt).takeUnretainedValue()
        let id = hotKeyID.id
        guard Thread.isMainThread else {
            CarbonHotkeyManager.logger.fault("Carbon hotkey callback arrived off the main thread; dropping action id=\(id, privacy: .public)")
            return noErr
        }
        Task { @MainActor [weak manager] in
            manager?.dispatch(id: id)
        }
        return noErr
    }
}
