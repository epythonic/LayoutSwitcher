import CoreGraphics
import Testing
@testable import LayoutSwitcher

@MainActor
struct KeyboardEventTapTests {
    @Test func hotkeyConsumedKeyDownSuppressesEventAndSkipsPipeline() {
        guard let event = Self.makeKeyDownEvent(keyCode: 12) else { return }
        let tap = KeyboardEventTap()
        var hotkeyCodes: [CGKeyCode] = []
        var pipelineCallCount = 0

        tap.hotkeyHandler = { keyEvent in
            hotkeyCodes.append(keyEvent.keyCode)
            return true
        }
        tap.onKeyEvent = { _ in
            pipelineCallCount += 1
        }

        let result = tap.handle(type: .keyDown, event: event)

        #expect(result == nil)
        #expect(hotkeyCodes == [12])
        #expect(pipelineCallCount == 0)
    }

    @Test func nonRepeatingKeyDownRunsHotkeyThenPipelineAndPassesEvent() {
        guard let event = Self.makeKeyDownEvent(keyCode: 13) else { return }
        let tap = KeyboardEventTap()
        var callOrder: [String] = []
        var pipelineKeyCode: CGKeyCode?

        tap.hotkeyHandler = { _ in
            callOrder.append("hotkey")
            return false
        }
        tap.onKeyEvent = { keyEvent in
            callOrder.append("pipeline")
            pipelineKeyCode = keyEvent.keyCode
        }

        let result = tap.handle(type: .keyDown, event: event)

        #expect(result != nil)
        #expect(callOrder == ["hotkey", "pipeline"])
        #expect(pipelineKeyCode == 13)
    }

    @Test func autoRepeatKeyDownIsIgnoredByHandlersAndPassedThrough() {
        guard let event = Self.makeKeyDownEvent(keyCode: 14) else { return }
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        let tap = KeyboardEventTap()
        var hotkeyCallCount = 0
        var pipelineCallCount = 0

        tap.hotkeyHandler = { _ in
            hotkeyCallCount += 1
            return false
        }
        tap.onKeyEvent = { _ in
            pipelineCallCount += 1
        }

        let result = tap.handle(type: .keyDown, event: event)

        #expect(result != nil)
        #expect(hotkeyCallCount == 0)
        #expect(pipelineCallCount == 0)
    }

    @Test func syntheticEventIsIgnoredByHandlersAndPassedThrough() {
        guard let event = Self.makeKeyDownEvent(keyCode: 15) else { return }
        SyntheticEventFilter.tag(event)
        let tap = KeyboardEventTap()
        var hotkeyCallCount = 0
        var pipelineCallCount = 0

        tap.hotkeyHandler = { _ in
            hotkeyCallCount += 1
            return false
        }
        tap.onKeyEvent = { _ in
            pipelineCallCount += 1
        }

        let result = tap.handle(type: .keyDown, event: event)

        #expect(result != nil)
        #expect(hotkeyCallCount == 0)
        #expect(pipelineCallCount == 0)
    }

    @Test func disabledTapEventIsPassedThrough() {
        guard let event = CGEvent(source: nil) else { return }
        let tap = KeyboardEventTap()

        let result = tap.handle(type: .tapDisabledByTimeout, event: event)

        #expect(result != nil)
    }

    private static func makeKeyDownEvent(keyCode: CGKeyCode) -> CGEvent? {
        CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
    }
}
