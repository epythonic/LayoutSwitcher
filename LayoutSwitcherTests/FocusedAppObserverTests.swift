import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct FocusedAppObserverTests {
    private struct StubRoleProvider: FocusedRoleProviding {
        let role: String?
        var subrole: String?

        func focusedRole() -> String? {
            role
        }

        func focusedSubrole() -> String? {
            subrole
        }
    }

    private final class StubObserver: FocusedAppObserving {
        var bundleID: String?
        var localizedName: String?
        var isSecureField: Bool
        var onChange: (@MainActor () -> Void)?

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

    @Test func classifiesDedicatedSecureRoleAsSecure() {
        #expect(FocusedFieldKind.classify(role: "AXSecureTextField", subrole: nil) == .secure)
    }

    @Test func classifiesSecureSubroleOnGenericTextRoleAsSecure() {
        // Some apps expose a generic text field with a secure subrole; widening
        // detection here is the whole point of the conservative field-type work.
        #expect(FocusedFieldKind.classify(role: "AXTextField", subrole: "AXSecureTextField") == .secure)
    }

    @Test func classifiesSearchSubroleAsSearch() {
        #expect(FocusedFieldKind.classify(role: "AXTextField", subrole: "AXSearchField") == .search)
    }

    @Test func classifiesPlainTextRolesAsText() {
        #expect(FocusedFieldKind.classify(role: "AXTextField", subrole: nil) == .text)
        #expect(FocusedFieldKind.classify(role: "AXTextArea", subrole: nil) == .text)
    }

    @Test func classifiesUnknownRoleAsUnknown() {
        #expect(FocusedFieldKind.classify(role: "AXButton", subrole: nil) == .unknown)
        #expect(FocusedFieldKind.classify(role: nil, subrole: nil) == .unknown)
    }

    @Test func observerDetectsSecureFieldFromSubrole() {
        let observer = FocusedAppObserver(
            roleProvider: StubRoleProvider(role: "AXTextField", subrole: "AXSecureTextField"),
            currentAppSnapshotProvider: {
                WorkspaceAppSnapshot(bundleID: "com.test.app", localizedName: "Test App")
            },
            observeWorkspaceActivation: { _ in nil },
            removeWorkspaceObserver: { _ in }
        )

        observer.start()

        #expect(observer.isSecureField)
        #expect(observer.focusedFieldKind == .secure)
    }

    @Test func observerExposesNonSecureFieldKindWithoutSuppressing() {
        let observer = FocusedAppObserver(
            roleProvider: StubRoleProvider(role: "AXTextField", subrole: "AXSearchField"),
            currentAppSnapshotProvider: {
                WorkspaceAppSnapshot(bundleID: "com.test.app", localizedName: "Test App")
            },
            observeWorkspaceActivation: { _ in nil },
            removeWorkspaceObserver: { _ in }
        )

        observer.start()

        #expect(!observer.isSecureField)
        #expect(observer.focusedFieldKind == .search)
    }

    @Test func startIsIdempotentAndDoesNotRegisterDuplicateObservers() {
        let token = NSObject()
        var observeCount = 0
        var snapshotReadCount = 0

        let observer = FocusedAppObserver(
            roleProvider: StubRoleProvider(role: nil),
            currentAppSnapshotProvider: {
                snapshotReadCount += 1
                return WorkspaceAppSnapshot(bundleID: "com.initial.app", localizedName: "Initial App")
            },
            observeWorkspaceActivation: { _ in
                observeCount += 1
                return token
            },
            removeWorkspaceObserver: { _ in }
        )

        observer.start()
        observer.start()

        #expect(observeCount == 1)
        #expect(snapshotReadCount == 1)
        #expect(observer.bundleID == "com.initial.app")
        #expect(observer.localizedName == "Initial App")
    }
}
