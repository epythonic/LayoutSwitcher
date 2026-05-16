import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct AccessibilityPermissionTests {
    @Test func initReadsInjectedTrustState() {
        let permission = makePermission(
            trustStatusProvider: { true }
        )

        #expect(permission.isTrusted)
    }

    @Test func refreshCallsGrantCallbackWhenTrustChangesToTrue() {
        let state = TestState()
        let permission = makePermission(
            trustStatusProvider: { state.trusted }
        )
        permission.onTrustGranted = {
            state.grantCount += 1
        }

        state.trusted = true
        permission.refresh()
        permission.refresh()

        #expect(permission.isTrusted)
        #expect(state.grantCount == 1)
    }

    @Test func promptUsesInjectedRequesterThenRefreshes() {
        let state = TestState()
        let permission = makePermission(
            trustStatusProvider: { state.trusted },
            trustPromptRequester: {
                state.promptCount += 1
                state.trusted = true
            }
        )

        permission.promptForTrust()

        #expect(state.promptCount == 1)
        #expect(permission.isTrusted)
    }

    @Test func openSystemSettingsUsesInjectedOpener() {
        let state = TestState()
        let permission = makePermission(
            trustStatusProvider: { false },
            systemSettingsOpener: { url in
                state.openedURL = url
            }
        )

        permission.openSystemSettings()

        #expect(state.openedURL?.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @Test func pollingUsesInjectedTimerFactoryAndStopsToken() {
        let state = TestState()
        let token = FakePollToken()
        let permission = makePermission(
            trustStatusProvider: { state.trusted },
            pollingTimerFactory: { interval, refresh in
                state.pollingIntervals.append(interval)
                state.factoryCallCount += 1
                state.tick = refresh
                return token
            }
        )
        permission.onTrustGranted = {
            state.grantCount += 1
        }

        permission.startPolling()
        permission.startPolling()
        state.trusted = true
        state.tick?()
        permission.stopPolling()
        permission.stopPolling()

        #expect(state.factoryCallCount == 1)
        #expect(state.pollingIntervals == [1.0])
        #expect(permission.isTrusted)
        #expect(state.grantCount == 1)
        #expect(token.invalidateCount == 1)
    }

    @Test func startAfterStopCreatesNewPollingTokenWithInjectedInterval() {
        let state = TestState()
        let firstToken = FakePollToken()
        let secondToken = FakePollToken()
        let permission = makePermission(
            pollingInterval: 0.25,
            trustStatusProvider: { false },
            pollingTimerFactory: { interval, _ in
                state.factoryCallCount += 1
                state.pollingIntervals.append(interval)
                return state.factoryCallCount == 1 ? firstToken : secondToken
            }
        )

        permission.startPolling()
        permission.stopPolling()
        permission.startPolling()
        permission.stopPolling()

        #expect(state.factoryCallCount == 2)
        #expect(state.pollingIntervals == [0.25, 0.25])
        #expect(firstToken.invalidateCount == 1)
        #expect(secondToken.invalidateCount == 1)
    }

    private func makePermission(
        pollingInterval: TimeInterval = 1.0,
        trustStatusProvider: @escaping AccessibilityPermission.TrustStatusProvider = { false },
        trustPromptRequester: @escaping AccessibilityPermission.TrustPromptRequester = {},
        systemSettingsOpener: @escaping AccessibilityPermission.SystemSettingsOpener = { _ in },
        pollingTimerFactory: @escaping AccessibilityPermission.PollingTimerFactory = { _, _ in FakePollToken() }
    ) -> AccessibilityPermission {
        AccessibilityPermission(
            pollingInterval: pollingInterval,
            trustStatusProvider: trustStatusProvider,
            trustPromptRequester: trustPromptRequester,
            systemSettingsOpener: systemSettingsOpener,
            pollingTimerFactory: pollingTimerFactory
        )
    }

    @MainActor
    private final class TestState {
        var trusted = false
        var grantCount = 0
        var promptCount = 0
        var factoryCallCount = 0
        var pollingIntervals: [TimeInterval] = []
        var openedURL: URL?
        var tick: (@MainActor () -> Void)?
    }

    @MainActor
    private final class FakePollToken: AccessibilityPermissionPolling {
        var invalidateCount = 0

        func invalidate() {
            invalidateCount += 1
        }
    }
}
