import Testing
@testable import LayoutSwitcher

@MainActor
struct VisualFeedbackPlayerTests {

    @Test func flashIsNoOpInLiveWhenDisabled() {
        let player = VisualFeedbackPlayer.live()
        player.flash(kind: .layoutSwitch, isEnabled: false) // Should not crash or throw
    }

    @Test func injectedFlashIsCalledWhenEnabled() {
        var flashedKinds: [CorrectionFeedbackKind] = []
        let player = VisualFeedbackPlayer { flashedKinds.append($0) }
        player.flash(kind: .duplicateLetter, isEnabled: true)
        #expect(flashedKinds == [.duplicateLetter])
    }

    @Test func injectedFlashIsNotCalledWhenDisabled() {
        var flashedKinds: [CorrectionFeedbackKind] = []
        let player = VisualFeedbackPlayer { flashedKinds.append($0) }
        player.flash(kind: .cupertino, isEnabled: false)
        #expect(flashedKinds.isEmpty)
    }
}
