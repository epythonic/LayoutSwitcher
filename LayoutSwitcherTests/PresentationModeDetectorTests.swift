import Testing
@testable import LayoutSwitcher

@MainActor
struct PresentationModeDetectorTests {
    @Test func detectsKeynoteAsPresenting() {
        let detector = PresentationModeDetector(
            frontmostBundleIDProvider: { "com.apple.iWork.Keynote" }
        )
        #expect(detector.isPresenting)
    }

    @Test func detectsSafariAsNotPresenting() {
        let detector = PresentationModeDetector(
            frontmostBundleIDProvider: { "com.apple.Safari" }
        )
        #expect(!detector.isPresenting)
    }

    @Test func nilBundleIDIsNotPresenting() {
        let detector = PresentationModeDetector(
            frontmostBundleIDProvider: { nil }
        )
        #expect(!detector.isPresenting)
    }

    @Test func customPresentationBundleIDIsDetected() {
        let detector = PresentationModeDetector(
            frontmostBundleIDProvider: { "com.example.Slides" },
            presentationBundleIDs: ["com.example.Slides"]
        )
        #expect(detector.isPresenting)
    }

    @Test func defaultSetContainsKeynote() {
        #expect(PresentationModeDetector.defaultPresentationBundleIDs.contains("com.apple.iWork.Keynote"))
    }
}
