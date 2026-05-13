import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct FocusedAppObserverTests {
    private struct StubRoleProvider: FocusedRoleProviding {
        let role: String?

        func focusedRole() -> String? {
            role
        }
    }

    private final class StubObserver: FocusedAppObserving {
        var bundleID: String?
        var localizedName: String?
        var isSecureField: Bool
        var onChange: (() -> Void)?

        init(bundleID: String? = nil, localizedName: String? = nil, isSecureField: Bool = false) {
            self.bundleID = bundleID
            self.localizedName = localizedName
            self.isSecureField = isSecureField
        }

        func refreshSecureFieldState() {}
    }

    @Test func observerReturnsBundleID() {
        let observer = StubObserver(bundleID: "com.test.app", localizedName: "TestApp")
        #expect(observer.bundleID == "com.test.app")
        #expect(observer.localizedName == "TestApp")
    }

    @Test func observerReturnsNilWhenUnknown() {
        let observer = StubObserver()
        #expect(observer.bundleID == nil)
        #expect(observer.localizedName == nil)
    }

    @Test func secureFieldFlagIsReadable() {
        let observer = StubObserver(isSecureField: true)
        #expect(observer.isSecureField)
    }

    @Test func startPublishesInjectedCurrentAppSnapshot() {
        let observer = FocusedAppObserver(
            roleProvider: StubRoleProvider(role: "AXSecureTextField"),
            currentAppSnapshotProvider: {
                WorkspaceAppSnapshot(bundleID: "com.test.app", localizedName: "Test App")
            },
            observeWorkspaceActivation: { _ in nil },
            removeWorkspaceObserver: { _ in }
        )

        var changes = 0
        observer.onChange = { changes += 1 }
        observer.start()

        #expect(observer.bundleID == "com.test.app")
        #expect(observer.localizedName == "Test App")
        #expect(observer.isSecureField)
        #expect(changes == 1)
    }

    @Test func activationObserverAndRemovalAreInjected() {
        let token = NSObject()
        var activationHandler: WorkspaceActivationHandler?
        var removedToken: NSObjectProtocol?

        let observer = FocusedAppObserver(
            roleProvider: StubRoleProvider(role: nil),
            currentAppSnapshotProvider: { nil },
            observeWorkspaceActivation: { handler in
                activationHandler = handler
                return token
            },
            removeWorkspaceObserver: { token in
                removedToken = token
            }
        )

        observer.start()
        activationHandler?(WorkspaceAppSnapshot(bundleID: "com.activated.app", localizedName: "Activated App"))

        #expect(observer.bundleID == "com.activated.app")
        #expect(observer.localizedName == "Activated App")

        observer.stop()
        #expect((removedToken as AnyObject?) === token)
    }
}
