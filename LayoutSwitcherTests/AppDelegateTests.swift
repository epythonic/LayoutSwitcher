import AppKit
import Testing
@testable import LayoutSwitcher

@MainActor
struct AppDelegateTests {
    @Test func applicationLaunchSkipsLiveServicesUnderXCTest() {
        let delegate = AppDelegate(
            onboardingCompletionStore: OnboardingCompletionStore(
                readCompleted: { true },
                writeCompleted: { _ in }
            )
        )

        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        #expect(!delegate.eventTap.isRunning)
        #expect(delegate.statusItemController == nil)
    }
}
