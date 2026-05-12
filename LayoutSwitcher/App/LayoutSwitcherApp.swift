import SwiftUI

/// SwiftUI entry point for the menu-bar utility.
///
/// The app intentionally exposes an empty `Settings` scene because all user interaction
/// is driven from the status item and custom windows managed by `AppDelegate`.
@main
struct LayoutSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Declares a placeholder settings scene required by SwiftUI app lifecycle.
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
