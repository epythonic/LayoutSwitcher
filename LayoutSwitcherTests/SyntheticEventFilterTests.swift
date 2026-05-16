import CoreGraphics
import Testing
@testable import LayoutSwitcher

@MainActor
struct SyntheticEventFilterTests {
    @Test func untaggedEventIsNotSynthetic() {
        guard let event = makeKeyEvent() else {
            #expect(Bool(false))
            return
        }

        #expect(!SyntheticEventFilter.isSynthetic(event))
    }

    @Test func taggedEventIsSynthetic() {
        guard let event = makeKeyEvent() else {
            #expect(Bool(false))
            return
        }

        SyntheticEventFilter.tag(event)

        #expect(SyntheticEventFilter.isSynthetic(event))
    }

    @Test func taggingDoesNotChangeEventKind() {
        guard let event = makeKeyEvent() else {
            #expect(Bool(false))
            return
        }

        let originalType = event.type

        SyntheticEventFilter.tag(event)

        #expect(event.type == originalType)
    }

    private func makeKeyEvent() -> CGEvent? {
        CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
    }
}
