import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct FocusedAppObserverTests {

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
}
