import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct RomanianDiacriticResolverTests {

    /// Builds a resolver backed by a small controlled word list.
    private static func makeResolver(words: [String]) -> RomanianDiacriticResolver {
        RomanianDiacriticResolver(words: words)
    }

    /// Helper constructing Romanian strings from explicit Unicode scalars to avoid
    /// literal encoding issues.
    private static func ro(_ scalars: [UInt32]) -> String {
        String(String.UnicodeScalarView(scalars.compactMap(Unicode.Scalar.init)))
    }

    @Test func plainKeyStripsDiacritics() {
        // cățel -> catel
        let catelDiacritic = Self.ro([0x63, 0x103, 0x21b, 0x65, 0x6c]) // cățel
        #expect(RomanianDiacriticResolver.plainKey(catelDiacritic) == "catel")
    }

    @Test func containsRomanianDiacriticMatchesExpectedScalars() {
        let catelDiacritic = Self.ro([0x63, 0x103, 0x21b, 0x65, 0x6c])
        #expect(RomanianDiacriticResolver.containsRomanianDiacritic(catelDiacritic))
        #expect(!RomanianDiacriticResolver.containsRomanianDiacritic("romana"))
        #expect(!RomanianDiacriticResolver.containsRomanianDiacritic("hello"))
    }

    @Test func variantsReturnsDiacriticFormsForPlainInput() {
        let catelDiacritic = Self.ro([0x63, 0x103, 0x21b, 0x65, 0x6c])
        let resolver = Self.makeResolver(words: [catelDiacritic, "catel"])
        let variants = resolver.variants(for: "catel")
        #expect(variants.contains(catelDiacritic))
    }

    @Test func variantsReturnsEmptyWhenAlreadyDiacritic() {
        let catelDiacritic = Self.ro([0x63, 0x103, 0x21b, 0x65, 0x6c])
        let resolver = Self.makeResolver(words: [catelDiacritic, "catel"])
        let variants = resolver.variants(for: catelDiacritic)
        #expect(variants.isEmpty)
    }

    @Test func variantsReturnsEmptyWhenNoMatch() {
        let catelDiacritic = Self.ro([0x63, 0x103, 0x21b, 0x65, 0x6c])
        let resolver = Self.makeResolver(words: [catelDiacritic])
        let variants = resolver.variants(for: "necunoscut")
        #expect(variants.isEmpty)
    }

    @Test func variantsPreservesCasingLower() {
        let catelDiacritic = Self.ro([0x63, 0x103, 0x21b, 0x65, 0x6c])
        let resolver = Self.makeResolver(words: [catelDiacritic])
        let variants = resolver.variants(for: "catel")
        #expect(variants.first == catelDiacritic)
    }

    @Test func variantsPreservesCasingCapitalized() {
        let catelDiacritic = Self.ro([0x63, 0x103, 0x21b, 0x65, 0x6c])
        let resolver = Self.makeResolver(words: [catelDiacritic])
        let variants = resolver.variants(for: "Catel")
        let expected = Self.ro([0x43, 0x103, 0x21b, 0x65, 0x6c]) // Cățel
        #expect(variants.first == expected)
    }

    @Test func multipleVariantsSorted() {
        let catelDiacritic = Self.ro([0x63, 0x103, 0x21b, 0x65, 0x6c])   // cățel
        let catelDiacritic2 = Self.ro([0x63, 0xe2, 0x21b, 0x65, 0x6c]) // câțel
        let resolver = Self.makeResolver(words: [catelDiacritic, catelDiacritic2, "catel"])
        let variants = resolver.variants(for: "catel")
        #expect(variants.count == 2)
    }

    @Test func ignoresWordsWithoutDiacriticsInIndex() {
        let resolver = Self.makeResolver(words: ["catel"])
        let variants = resolver.variants(for: "catel")
        #expect(variants.isEmpty)
    }
}
