import AppKit
import Foundation

/// Detects whether the frontmost application is a known presentation / slideshow
/// app so that automatic layout switches can be suppressed.
@MainActor
final class PresentationModeDetector {
    private let frontmostBundleIDProvider: () -> String?
    private let presentationBundleIDs: Set<String>

    init(
        frontmostBundleIDProvider: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        },
        presentationBundleIDs: Set<String> = [
            "com.apple.iWork.Keynote",
            "com.microsoft.Powerpoint",
            "com.microsoft.PowerPoint",
            "us.zoom.xos",
            "com.apple.QuickTimePlayerX",
            "com.apple.Pages",
        ]
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
