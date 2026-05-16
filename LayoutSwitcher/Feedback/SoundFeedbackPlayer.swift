import AppKit

/// Plays system sounds for automatic correction feedback.
@MainActor
struct SoundFeedbackPlayer {
    typealias PlaySound = @MainActor (CorrectionFeedbackKind) -> Void

    private let playClosure: PlaySound

    init(_ closure: @escaping PlaySound) {
        self.playClosure = closure
    }

    /// Plays the chosen system sound if feedback is enabled.
    func play(kind: CorrectionFeedbackKind, isEnabled: Bool) {
        guard isEnabled else { return }
        playClosure(kind)
    }

    /// Creates a production player that resolves sounds via `NSSound`.
    static func live() -> SoundFeedbackPlayer {
        SoundFeedbackPlayer { kind in
            NSSound(named: kind.systemSoundName)?.play()
        }
    }
}
