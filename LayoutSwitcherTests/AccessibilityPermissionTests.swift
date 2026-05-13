import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct AccessibilityPermissionTests {
    @Test func initReadsInjectedTrustState() {
        let permission = AccessibilityPermission(
            trustStatusProvider: { true }
        )

        #expect(permission.isTrusted)
    }

    @Test func refreshCallsGrantCallbackWhenTrustChangesToTrue() {
        var trusted = false
        var grantCount = 0
        let permission = AccessibilityPermission(
            trustStatusProvider: { trusted }
        )
        permission.onTrustGranted = {
            grantCount += 1
        }

        trusted = true
        permission.refresh()
        permission.refresh()

        #expect(permission.isTrusted)
        #expect(grantCount == 1)
    }

    @Test func promptUsesInjectedRequesterThenRefreshes() {
        var trusted = false
        var promptCount = 0
        let permission = AccessibilityPermission(
            trustStatusProvider: { trusted },
            trustPromptRequester: {
                promptCount += 1
                trusted = true
            }
        )

        permission.promptForTrust()

        #expect(promptCount == 1)
        #expect(permission.isTrusted)
    }

    @Test func openSystemSettingsUsesInjectedOpener() {
        var openedURL: URL?
        let permission = AccessibilityPermission(
            trustStatusProvider: { false },
            systemSettingsOpener: { url in
                openedURL = url
            }
        )

        permission.openSystemSettings()

        #expect(openedURL?.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @Test func pollingUsesInjectedTimerFactoryAndStopsToken() {
        var trusted = false
        var factoryCallCount = 0
        var grantCount = 0
        var tick: (@MainActor () -> Void)?
        let token = FakePollToken()
        let permission = AccessibilityPermission(
            trustStatusProvider: { trusted },
            pollingTimerFactory: { refresh in
                factoryCallCount += 1
                tick = refresh
                return token
            }
        )
        permission.onTrustGranted = {
            grantCount += 1
        }

        permission.startPolling()
        permission.startPolling()
        trusted = true
        tick?()
        permission.stopPolling()
        permission.stopPolling()

        #expect(factoryCallCount == 1)
        #expect(permission.isTrusted)
        #expect(grantCount == 1)
        #expect(token.invalidateCount == 1)
    }

    @MainActor
    private final class FakePollToken: AccessibilityPermissionPolling {
        var invalidateCount = 0

        func invalidate() {
            invalidateCount += 1
        }
    }
}
