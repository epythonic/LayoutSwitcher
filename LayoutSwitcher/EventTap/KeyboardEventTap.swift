import AppKit
@preconcurrency import CoreGraphics
import os

/// Global event tap wrapper responsible for forwarding user input into the pipeline.
@MainActor
final class KeyboardEventTap {
    static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "EventTap")

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onKeyEvent: ((KeyEvent) -> Void)?
    /// Returns true if the event was consumed (a hotkey fired) and should be suppressed system-wide.
    var hotkeyHandler: ((KeyEvent) -> Bool)?

    /// Indicates whether low-level event tap is currently installed.
    var isRunning: Bool { eventTap != nil }

    /// Installs global event tap for keyboard and selected mouse events.
    func start() {
        guard eventTap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: KeyboardEventTap.tapCallback,
            userInfo: selfPtr
        ) else {
            Self.logger.error("Failed to create event tap (Accessibility permission?)")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        Self.logger.info("Event tap started")
    }

    /// Removes global event tap and runloop source.
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        Self.logger.info("Event tap stopped")
    }

    /// Handles raw callback events, filtering synthetic input and dispatching normalized events.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Self.logger.warning("Tap disabled (\(type.rawValue, privacy: .public)) — re-enabling")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if SyntheticEventFilter.isSynthetic(event) {
            return Unmanaged.passUnretained(event)
        }

        if let keyEvent = KeyEvent(cgEvent: event), !keyEvent.isAutoRepeat {
            if hotkeyHandler?(keyEvent) == true {
                return nil
            }
            onKeyEvent?(keyEvent)
        }

        return Unmanaged.passUnretained(event)
    }

    private static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let tap = Unmanaged<KeyboardEventTap>.fromOpaque(refcon).takeUnretainedValue()
        return MainActor.assumeIsolated {
            tap.handle(type: type, event: event)
        } ?? Unmanaged.passUnretained(event)
    }
}
