import AppKit
import SwiftUI

/// Minimal recorder control that captures the next keydown and emits a hotkey definition.
struct KeyRecorderView: NSViewRepresentable {
    /// Whether the recorder should currently capture the next keydown.
    @Binding var isRecording: Bool
    /// Receives a captured definition or `nil` when recording is cancelled.
    let onCommit: (HotkeyDefinition?) -> Void

    /// Creates the AppKit event-monitor coordinator.
    func makeCoordinator() -> Coordinator {
        Coordinator(onCommit: onCommit)
    }

    /// Provides an invisible AppKit host view for local event monitoring.
    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    /// Starts or stops recording based on SwiftUI state.
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.setRecording(isRecording)
    }

    /// Ensures the local monitor is removed when SwiftUI tears down the view.
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopRecording()
    }

    /// Coordinates an AppKit key event monitor that emits a single hotkey definition.
    @MainActor
    final class Coordinator: NSObject {
        /// AppKit local event monitor token.
        private var monitor: Any?
        /// Current capture state used to keep recording idempotent.
        private var isRecording = false
        /// Commit callback forwarded from `KeyRecorderView`.
        private let onCommit: (HotkeyDefinition?) -> Void

        /// Creates a coordinator with the recorder commit callback.
        init(onCommit: @escaping (HotkeyDefinition?) -> Void) {
            self.onCommit = onCommit
        }

        /// Starts or stops the recorder based on visibility.
        func setRecording(_ recording: Bool) {
            if recording {
                startRecording()
            } else {
                stopRecording()
            }
        }

        /// Starts consuming keydown events for a one-shot hotkey capture.
        private func startRecording() {
            guard !isRecording else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return nil }
                if event.keyCode == 53 {
                    self.onCommit(nil)
                    self.stopRecording()
                    return nil
                }

                let definition = HotkeyDefinition(
                    keyCode: event.keyCode,
                    modifiers: Self.modifiers(from: event.modifierFlags)
                )

                self.onCommit(definition)
                self.stopRecording()
                return nil
            }
            isRecording = true
        }

        /// Stops event capture and releases monitoring resources.
        func stopRecording() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            isRecording = false
        }

        /// Extracts the supported modifier flags for hotkey matching.
        private static func modifiers(from flags: NSEvent.ModifierFlags) -> HotkeyDefinition.ModifierMask {
            var mask: HotkeyDefinition.ModifierMask = []
            if flags.contains(.control) { mask.insert(.control) }
            if flags.contains(.option) { mask.insert(.option) }
            if flags.contains(.shift) { mask.insert(.shift) }
            if flags.contains(.command) { mask.insert(.command) }
            return mask
        }
    }
}
