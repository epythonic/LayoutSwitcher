import Testing
@testable import LayoutSwitcher

@MainActor
struct HelpContentTests {
    @Test func helpContainsPrivacySection() {
        #expect(HelpContent.sections.contains { $0.id == "privacy" })
    }

    @Test func privacySectionContainsKeyPhrases() {
        guard let privacySection = HelpContent.sections.first(where: { $0.id == "privacy" }) else {
            Issue.record("Privacy section not found")
            return
        }

        #expect(privacySection.bodyEN.contains("Accessibility"))
        #expect(privacySection.bodyEN.contains("local"))
        #expect(privacySection.bodyEN.contains("server"))
        #expect(privacySection.bodyEN.contains("secure text fields"))
        #expect(privacySection.bodyEN.contains("Synthetic events"))
        #expect(privacySection.bodyEN.contains("Preferences → Exclusions"))
        #expect(privacySection.bodyRU.contains("Accessibility"))
        #expect(privacySection.bodyRU.contains("локально"))
        #expect(privacySection.bodyRU.contains("сервер"))
        #expect(privacySection.bodyRU.contains("secure text fields"))
        #expect(privacySection.bodyRU.contains("Синтетические события"))
        #expect(privacySection.bodyRU.contains("Настройках → Исключениях"))
    }
}
