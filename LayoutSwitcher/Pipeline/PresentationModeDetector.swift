import AppKit
import Foundation

/// Detects whether the frontmost application is a known presentation / slideshow
/// app so that automatic layout switches can be suppressed.
@MainActor
struct PresentationModeDetector {
    private let frontmostBundleIDProvider: @MainActor () -> String?
    private let presentationBundleIDs: Set<String>

    /// Creates a detector backed by the provided workspace.
    init(
        workspace: NSWorkspace,
        presentationBundleIDs: Set<String> = PresentationModeDetector.defaultPresentationBundleIDs
    ) {
        self.init(
            frontmostBundleIDProvider: {
                workspace.frontmostApplication?.bundleIdentifier
            },
            presentationBundleIDs: presentationBundleIDs
        )
    }

    /// Creates a detector with injectable frontmost-app lookup for deterministic tests.
    init(
        frontmostBundleIDProvider: @escaping @MainActor () -> String?,
        presentationBundleIDs: Set<String> = PresentationModeDetector.defaultPresentationBundleIDs
    ) {
        self.frontmostBundleIDProvider = frontmostBundleIDProvider
        self.presentationBundleIDs = presentationBundleIDs
    }

    /// Returns `true` when the currently focused app is a known presentation app.
    var isPresenting: Bool {
        guard let bundleID = frontmostBundleIDProvider() else { return false }
        return presentationBundleIDs.contains(bundleID)
    }

    static let defaultPresentationBundleIDs: Set<String> = [
        "com.apple.iWork.Keynote",
        "com.microsoft.Powerpoint",
        "com.microsoft.PowerPoint",
        "us.zoom.xos",
        "com.apple.QuickTimePlayerX",
        "com.apple.Pages", // Pages can be used for presentations
    ]
}
