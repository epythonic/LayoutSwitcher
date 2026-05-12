import AppKit

/// Plays system sounds for automatic-switch feedback.
@MainActor
struct SoundFeedbackPlayer {
    private let playClosure: (SoundFeedbackKind) -> Void

    init(_ closure: @escaping (SoundFeedbackKind) -> Void) {
        self.playClosure = closure
    }

    /// Plays the chosen system sound if feedback is enabled.
    func play(kind: SoundFeedbackKind, isEnabled: Bool) {
        guard isEnabled else { return }
        playClosure(kind)
    }

    /// Production player that resolves sounds via `NSSound`.
    static let live = SoundFeedbackPlayer { kind in
        let name: String = {
            switch kind {
            case .tink:  return "Tink"
            case .glass: return "Glass"
            }
        }()
        NSSound(named: name)?.play()
    }
}
