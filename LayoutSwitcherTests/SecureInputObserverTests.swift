import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct SecureInputObserverTests {
    @Test func startPollsImmediatelyAndPublishesChange() {
        let state = TestState()
        let observer = makeObserver(
            secureInputStatusProvider: { true },
            pollingTimerFactory: { _, _ in FakePollToken() }
        )
        observer.onChange = { state.changes.append($0) }

        observer.start()

        #expect(observer.isSecureInputEnabled)
        #expect(state.changes == [true])
    }

    @Test func timerTickPublishesOnlyStateChanges() {
        let state = TestState()
        let observer = makeObserver(
            secureInputStatusProvider: { state.secureInputEnabled },
            pollingTimerFactory: { _, refresh in
                state.tick = refresh
                return FakePollToken()
            }
        )
        observer.onChange = { state.changes.append($0) }

        observer.start()
        state.tick?()
        state.secureInputEnabled = true
        state.tick?()
        state.tick?()
        state.secureInputEnabled = false
        state.tick?()

        #expect(state.changes == [true, false])
    }

    @Test func startAndStopAreIdempotent() {
        let state = TestState()
        let token = FakePollToken()
        let observer = makeObserver(
            secureInputStatusProvider: { false },
            pollingTimerFactory: { _, _ in
                state.factoryCallCount += 1
                return token
            }
        )

        observer.start()
        observer.start()
        observer.stop()
        observer.stop()

        #expect(state.factoryCallCount == 1)
        #expect(token.invalidateCount == 1)
    }

    @Test func startAfterStopCreatesNewPollingToken() {
        let state = TestState()
        let firstToken = FakePollToken()
        let secondToken = FakePollToken()
        let observer = makeObserver(
            secureInputStatusProvider: { false },
            pollingTimerFactory: { _, _ in
                state.factoryCallCount += 1
                return state.factoryCallCount == 1 ? firstToken : secondToken
            }
        )

        observer.start()
        observer.stop()
        observer.start()
        observer.stop()

        #expect(state.factoryCallCount == 2)
        #expect(firstToken.invalidateCount == 1)
        #expect(secondToken.invalidateCount == 1)
    }

    private func makeObserver(
        interval: TimeInterval = 1.5,
        secureInputStatusProvider: @escaping SecureInputObserver.SecureInputStatusProvider = { false },
        pollingTimerFactory: @escaping SecureInputObserver.PollingTimerFactory = { _, _ in FakePollToken() }
    ) -> SecureInputObserver {
        SecureInputObserver(
            interval: interval,
            secureInputStatusProvider: secureInputStatusProvider,
            pollingTimerFactory: pollingTimerFactory
        )
    }

    @MainActor
    private final class TestState {
        var secureInputEnabled = false
        var changes: [Bool] = []
        var factoryCallCount = 0
        var tick: (@MainActor () -> Void)?
    }

    @MainActor
    private final class FakePollToken: SecureInputPolling {
        var invalidateCount = 0

        func invalidate() {
            invalidateCount += 1
        }
    }
}
