import Testing
@testable import LayoutSwitcher

@MainActor
struct NonConvertibleTokenGuardTests {

    @Test func keepsURL() {
        #expect(NonConvertibleTokenGuard.shouldKeep("https://example.com"))
    }

    @Test func keepsFTP() {
        #expect(NonConvertibleTokenGuard.shouldKeep("ftp://server.local"))
    }

    @Test func keepsPath() {
        #expect(NonConvertibleTokenGuard.shouldKeep("~/Documents/file.txt"))
    }

    @Test func keepsAbsolutePath() {
        #expect(NonConvertibleTokenGuard.shouldKeep("/usr/local/bin"))
    }

    @Test func keepsDottedIdentifier() {
        #expect(NonConvertibleTokenGuard.shouldKeep("com.example.bundle"))
    }

    @Test func keepsEmailHandle() {
        #expect(NonConvertibleTokenGuard.shouldKeep("user@host"))
    }

    @Test func keepsWWW() {
        #expect(NonConvertibleTokenGuard.shouldKeep("www.example.com"))
    }

    @Test func allowsRegularWord() {
        #expect(!NonConvertibleTokenGuard.shouldKeep("hello"))
    }

    @Test func allowsWordWithWhitespace() {
        #expect(!NonConvertibleTokenGuard.shouldKeep("hello world"))
    }

    @Test func emptyTokenIsNotKept() {
        #expect(!NonConvertibleTokenGuard.shouldKeep(""))
    }

    @Test func isTechnicalBoundaryForAt() {
        #expect(NonConvertibleTokenGuard.isTechnicalBoundary("@"))
    }

    @Test func isTechnicalBoundaryForDot() {
        #expect(NonConvertibleTokenGuard.isTechnicalBoundary("."))
    }

    @Test func isNotTechnicalBoundaryForComma() {
        #expect(!NonConvertibleTokenGuard.isTechnicalBoundary(","))
    }
}
