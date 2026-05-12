import CoreGraphics
import Testing
@testable import LayoutSwitcher

@MainActor
struct KeyEventTests {

    @Test func defaultInitSetsFields() {
        let event = KeyEvent(
            kind: .keyDown,
            keyCode: 12,
            flags: [.maskShift],
            unicode: "Q",
            isAutoRepeat: true,
            sourcePID: 42,
            timestamp: 100
        )
        #expect(event.kind == .keyDown)
        #expect(event.keyCode == 12)
        #expect(event.flags == [.maskShift])
        #expect(event.unicode == "Q")
        #expect(event.isAutoRepeat)
        #expect(event.sourcePID == 42)
        #expect(event.timestamp == 100)
    }

    @Test func defaultInitUsesDefaults() {
        let event = KeyEvent(keyCode: 1, unicode: "a")
        #expect(event.kind == .keyDown)
        #expect(event.flags == [])
        #expect(!event.isAutoRepeat)
        #expect(event.sourcePID == 0)
        #expect(event.timestamp == 0)
    }

    @Test func cgEventKeyDownKind() {
        guard let cgEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else {
            return
        }
        let event = KeyEvent(cgEvent: cgEvent)
        #expect(event != nil)
        #expect(event?.kind == .keyDown)
    }

    @Test func cgEventFlagsChangedKind() {
        guard let cgEvent = CGEvent(source: nil) else { return }
        cgEvent.type = .flagsChanged
        let event = KeyEvent(cgEvent: cgEvent)
        #expect(event?.kind == .flagsChanged)
    }
}
