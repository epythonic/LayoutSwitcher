import ApplicationServices
import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct AXElementBridgeTests {
    @Test func systemWideAXElementPassesTypeCheck() {
        let element = AXUIElementCreateSystemWide()

        let bridged = AXElementBridge.element(from: element)

        #expect(bridged != nil)
    }

    @Test func stringCFTypeIsRejected() {
        let value = "not-an-ax-element" as CFString

        let bridged = AXElementBridge.element(from: value)

        #expect(bridged == nil)
    }

    @Test func numberCFTypeIsRejected() {
        let value = NSNumber(value: 42)

        let bridged = AXElementBridge.element(from: value)

        #expect(bridged == nil)
    }
}
