import Testing
@testable import LayoutSwitcher

@MainActor
struct VisualFeedbackPlayerTests {

    @Test func flashIsNoOpInLiveWhenDisabled() {
        let player = VisualFeedbackPlayer.live
        player.flash(isEnabled: false) // Should not crash or throw
    }

    @Test func injectedFlashIsCalledWhenEnabled() {
        var called = false
        let player = VisualFeedbackPlayer { called = true }
        player.flash(isEnabled: true)
        #expect(called)
    }

    @Test func injectedFlashIsNotCalledWhenDisabled() {
        var called = false
        let player = VisualFeedbackPlayer { called = true }
        player.flash(isEnabled: false)
        #expect(!called)
    }
}
