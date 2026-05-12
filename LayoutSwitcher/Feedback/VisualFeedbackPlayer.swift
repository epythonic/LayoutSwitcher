import Foundation

/// Triggers visual feedback (menu-bar flash) after successful automatic switches.
@MainActor
struct VisualFeedbackPlayer {
    private let flashClosure: () -> Void

    init(_ closure: @escaping () -> Void) {
        self.flashClosure = closure
    }

    /// Triggers the flash if visual feedback is enabled.
    func flash(isEnabled: Bool) {
        guard isEnabled else { return }
        flashClosure()
    }

    /// No-op placeholder for contexts that do not wire visual feedback.
    static let live = VisualFeedbackPlayer {}
}
