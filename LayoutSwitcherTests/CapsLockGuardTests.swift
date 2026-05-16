import Testing
@testable import LayoutSwitcher

@MainActor
struct CapsLockGuardTests {
    @Test func captureAndDisableDoesNothingWhenCapsLockIsOff() {
        var setStates: [Bool] = []
        let guarder = CapsLockGuard(
            readCapsLockState: { false },
            setCapsLockState: { state in
                setStates.append(state)
                return true
            }
        )

        guarder.captureAndDisable()
        guarder.restore()

        #expect(setStates.isEmpty)
    }

    @Test func captureAndDisableTurnsOffCapsLockAndRestoreTurnsItBackOn() {
        var currentState = true
        var setStates: [Bool] = []
        let guarder = CapsLockGuard(
            readCapsLockState: { currentState },
            setCapsLockState: { state in
                setStates.append(state)
                currentState = state
                return true
            }
        )

        guarder.captureAndDisable()
        guarder.restore()

        #expect(setStates == [false, true])
        #expect(currentState)
    }

    @Test func failedDisableDoesNotRestoreLater() {
        var setStates: [Bool] = []
        let guarder = CapsLockGuard(
            readCapsLockState: { true },
            setCapsLockState: { state in
                setStates.append(state)
                return false
            }
        )

        guarder.captureAndDisable()
        guarder.restore()

        #expect(setStates == [false])
    }

    @Test func restoreIsIdempotentAfterCapturedStateIsRestored() {
        var setStates: [Bool] = []
        let guarder = CapsLockGuard(
            readCapsLockState: { true },
            setCapsLockState: { state in
                setStates.append(state)
                return true
            }
        )

        guarder.captureAndDisable()
        guarder.restore()
        guarder.restore()

        #expect(setStates == [false, true])
    }
}
