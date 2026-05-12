import Testing
@testable import LayoutSwitcher

@MainActor
struct StatusItemControllerTests {
    @Test func languageBadgeConvertsCodeToTwoLetterUppercase() {
        let badge = StatusItemController.languageBadge("en")
        #expect(badge == "EN")
    }

    @Test func languageBadgeHandlesMixedCase() {
        #expect(StatusItemController.languageBadge("Ru") == "RU")
        #expect(StatusItemController.languageBadge("uK") == "UK")
        #expect(StatusItemController.languageBadge("Ro") == "RO")
    }

    @Test func languageBadgeHandlesLongCodes() {
        #expect(StatusItemController.languageBadge("english") == "EN")
        #expect(StatusItemController.languageBadge("russian") == "RU")
    }
}
