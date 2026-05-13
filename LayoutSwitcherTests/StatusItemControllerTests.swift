import AppKit
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

    @Test func statusBarLanguageIconIsTemplateImage() {
        let image = StatusBarIconRenderer.image(for: .language(code: "ru"))

        #expect(image.isTemplate)
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    @Test func statusBarFallbackIconIsTemplateImage() {
        let image = StatusBarIconRenderer.image(for: .fallback)

        #expect(image.isTemplate)
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }
}
