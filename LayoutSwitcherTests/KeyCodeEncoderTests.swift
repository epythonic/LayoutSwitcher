import CoreGraphics
import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct KeyCodeEncoderTests {

    /// Finds the first enabled English layout and returns its unicode key layout data.
    private static func englishLayoutData() -> Data? {
        let manager = InputSourceManager()
        let layouts = manager.keyboardLayouts()
        guard let source = layouts.first(where: {
            ($0.primaryLanguage ?? "").hasPrefix("en") || $0.id.contains("ABC")
        }) else { return nil }
        return source.unicodeKeyLayoutData()
    }

    @Test func encodesLowercaseA() async throws {
        guard let data = Self.englishLayoutData() else {
            // No English layout available on this system — test is not applicable.
            return
        }
        let encoded = KeyCodeEncoder.encode("a", layoutData: data)
        #expect(encoded != nil)
        #expect(encoded?.keyCode == 0)
        #expect(encoded?.flags == [])
    }

    @Test func encodesUppercaseAWithShift() async throws {
        guard let data = Self.englishLayoutData() else { return }
        let encoded = KeyCodeEncoder.encode("A", layoutData: data)
        #expect(encoded != nil)
        #expect(encoded?.flags.contains(.maskShift) == true)
    }

    @Test func encodesDigit() async throws {
        guard let data = Self.englishLayoutData() else { return }
        let encoded = KeyCodeEncoder.encode("1", layoutData: data)
        #expect(encoded != nil)
    }

    @Test func failsForUnsupportedCharacter() async throws {
        guard let data = Self.englishLayoutData() else { return }
        // U+1F600 (emoji) is unlikely to map on a standard US layout.
        let encoded = KeyCodeEncoder.encode("\u{1F600}", layoutData: data)
        #expect(encoded == nil)
    }

    @Test func layoutDataAvailableForAtLeastOneKeyboard() async throws {
        let manager = InputSourceManager()
        let layouts = manager.keyboardLayouts()
        let anyData = layouts.lazy.compactMap { $0.unicodeKeyLayoutData() }.first
        #expect(anyData != nil, "No keyboard layout data available on this system")
    }
}
