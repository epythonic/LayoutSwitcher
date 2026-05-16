import Testing
@testable import LayoutSwitcher

@MainActor
struct RussianYoResolverTests {
    @Test func plainKeyConvertsYoToYe() {
        #expect(RussianYoResolver.plainKey("ёжик") == "ежик")
    }

    @Test func unambiguousCorrectionReturnsYoVariant() {
        let resolver = RussianYoResolver(words: ["ёжик"])
        #expect(resolver.unambiguousCorrection(for: "ежик") == "ёжик")
    }

    @Test func ambiguousPlainWordReturnsNil() {
        let resolver = RussianYoResolver(words: ["все", "всё"])
        #expect(resolver.unambiguousCorrection(for: "все") == nil)
    }

    @Test func plainWordOverrideReturnsNil() {
        let resolver = RussianYoResolver(words: ["передохнёт", "передохнет"])
        #expect(resolver.unambiguousCorrection(for: "передохнет") == nil)
    }

    @Test func preferredPlainCorrectionCanOverrideCorpusCompatibilitySpelling() {
        let resolver = RussianYoResolver(
            words: ["ёжик", "ежик"],
            preferredPlainCorrections: ["ежик"]
        )
        #expect(resolver.unambiguousCorrection(for: "ежик") == "ёжик")
    }

    @Test func ambiguousWordStaysUnchangedWithoutPreferredOverride() {
        let resolver = RussianYoResolver(
            words: ["всё", "все"],
            preferredPlainCorrections: ["ежик"]
        )
        #expect(resolver.unambiguousCorrection(for: "все") == nil)
    }

    @Test func capitalizedCorrectionKeepsCasing() {
        let resolver = RussianYoResolver(words: ["ёлка"])
        #expect(resolver.unambiguousCorrection(for: "Елка") == "Ёлка")
    }
}
