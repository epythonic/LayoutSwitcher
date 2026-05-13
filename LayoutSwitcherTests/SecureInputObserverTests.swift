import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct SecureInputObserverTests {
    @Test func startPollsImmediatelyAndPublishesChange() {
        var changes: [Bool] = []
        let observer = SecureInputObserver(
            secureInputStatusProvider: { true },
            pollingTimerFactory: { _, _ in FakePollToken() }
        )
        observer.onChange = { changes.append($0) }

        observer.start()

        #expect(observer.isSecureInputEnabled)
        #expect(changes == [true])
    }

    @Test func timerTickPublishesOnlyStateChanges() {
        var secureInputEnabled = false
        var tick: (@MainActor () -> Void)?
        var changes: [Bool] = []
        let observer = SecureInputObserver(
            secureInputStatusProvider: { secureInputEnabled },
            pollingTimerFactory: { _, refresh in
                tick = refresh
                return FakePollToken()
            }
        )
        observer.onChange = { changes.append($0) }

        observer.start()
        tick?()
        secureInputEnabled = true
        tick?()
        tick?()
        secureInputEnabled = false
        tick?()

        #expect(changes == [true, false])
    }

    @Test func startAndStopAreIdempotent() {
        var factoryCallCount = 0
        let token = FakePollToken()
        let observer = SecureInputObserver(
            secureInputStatusProvider: { false },
            pollingTimerFactory: { _, _ in
                factoryCallCount += 1
                return token
            }
        )

        observer.start()
        observer.start()
        observer.stop()
        observer.stop()

        #expect(factoryCallCount == 1)
        #expect(token.invalidateCount == 1)
    }

    @MainActor
    private final class FakePollToken: SecureInputPolling {
        var invalidateCount = 0

        func invalidate() {
            invalidateCount += 1
        }
    }
}
