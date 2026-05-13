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

    @Test func injectedHelpLoaderFallsBackToEnglishBody() {
        var loader = HelpBodyLoader { language in
            switch language {
            case .en:
                """
                ## overview
                English overview body
                """
            case .ru, .ro, .uk:
                nil
            }
        }

        let body = loader.body(for: "overview", language: .ru)

        #expect(body == "English overview body")
    }

    @Test func injectedHelpLoaderCachesLoadedMarkdown() {
        var loadCount = 0
        var loader = HelpBodyLoader { _ in
            loadCount += 1
            return """
            ## overview
            Cached body
            """
        }

        let first = loader.body(for: "overview", language: .en)
        let second = loader.body(for: "overview", language: .en)

        #expect(first == "Cached body")
        #expect(second == "Cached body")
        #expect(loadCount == 1)
    }
}
