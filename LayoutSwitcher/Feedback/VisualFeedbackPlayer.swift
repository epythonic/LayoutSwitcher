import Foundation

/// Triggers visual feedback after successful automatic corrections.
@MainActor
struct VisualFeedbackPlayer {
    typealias Flash = @MainActor (CorrectionFeedbackKind) -> Void

    private let flashClosure: Flash

    init(_ closure: @escaping Flash) {
        self.flashClosure = closure
    }

    /// Triggers the flash if visual feedback is enabled.
    func flash(kind: CorrectionFeedbackKind, isEnabled: Bool) {
        guard isEnabled else { return }
        flashClosure(kind)
    }

    /// Creates a no-op placeholder for contexts that do not wire visual feedback.
    static func live() -> VisualFeedbackPlayer {
        VisualFeedbackPlayer { _ in }
    }
}
