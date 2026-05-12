import AppKit
import SwiftUI

/// Minimal recorder control that captures the next keydown and emits a hotkey definition.
struct KeyRecorderView: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCommit: (HotkeyDefinition?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCommit: onCommit)
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.setRecording(isRecording)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopRecording()
    }

    /// Coordinates an AppKit key event monitor that emits a single hotkey definition.
    @MainActor
    final class Coordinator: NSObject {
        private var monitor: Any?
        private var isRecording = false
        private let onCommit: (HotkeyDefinition?) -> Void

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
