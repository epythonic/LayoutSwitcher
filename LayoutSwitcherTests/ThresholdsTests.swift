import Testing
@testable import LayoutSwitcher

@MainActor
struct ThresholdsTests {

    @Test func defaultThresholdsHaveSaneValues() {
        let t = DetectionThresholds.default
        #expect(t.minWordLength == 3)
        #expect(t.maxWordLength == 30)
        #expect(t.shortWordStrictMinLength == 2)
        #expect(t.nGramMargin == 0.5)
        #expect(t.activeDictionaryOverrideMargin == 0.75)
        #expect(t.naturalLanguageMinWordLength == 5)
        #expect(t.naturalLanguageMinimumConfidence == 0.45)
        #expect(t.naturalLanguageTieBreakMargin == 0.15)
    }

    @Test func conservativeRaisesMargins() {
        let t = DetectionSensitivity.conservative.thresholds
        #expect(t.nGramMargin > DetectionThresholds.default.nGramMargin)
        #expect(t.activeDictionaryOverrideMargin > DetectionThresholds.default.activeDictionaryOverrideMargin)
    }

    @Test func aggressiveLowersMargins() {
        let t = DetectionSensitivity.aggressive.thresholds
        #expect(t.nGramMargin < DetectionThresholds.default.nGramMargin)
        #expect(t.activeDictionaryOverrideMargin < DetectionThresholds.default.activeDictionaryOverrideMargin)
    }

    @Test func balancedEqualsDefault() {
        let t = DetectionSensitivity.balanced.thresholds
        #expect(t.nGramMargin == DetectionThresholds.default.nGramMargin)
        #expect(t.activeDictionaryOverrideMargin == DetectionThresholds.default.activeDictionaryOverrideMargin)
    }

    @Test func sensitivityLocalizedTitlesAreNonEmpty() {
        #expect(!DetectionSensitivity.conservative.localizedTitle.isEmpty)
        #expect(!DetectionSensitivity.balanced.localizedTitle.isEmpty)
        #expect(!DetectionSensitivity.aggressive.localizedTitle.isEmpty)
    }

    @Test func allCasesExist() {
        #expect(DetectionSensitivity.allCases.count == 3)
    }
}
