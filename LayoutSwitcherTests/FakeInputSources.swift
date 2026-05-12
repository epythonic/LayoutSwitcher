import Carbon.HIToolbox
import Foundation
@testable import LayoutSwitcher

/// Deterministic stand-in for `InputSourceManager` used in tests so multiple
/// suites can run in parallel without touching the real system input source.
/// All side effects are local to the instance.
@MainActor
final class FakeInputSources: InputSourceManaging {
    private(set) var current: InputSource?
    private(set) var layouts: [InputSource]
    /// Records of `select(_:)` calls — useful for asserting pipeline behavior.
    private(set) var selectedHistory: [String] = []
    /// Optional override forcing `select` to fail (e.g. simulating TIS errors).
    var selectFailureStatus: OSStatus?

    /// Builds a fake with the given layouts; the first one is treated as current.
    init(layouts: [InputSource], currentID: String? = nil) {
        self.layouts = layouts
        if let currentID, let match = layouts.first(where: { $0.id == currentID }) {
            self.current = match
        } else {
            self.current = layouts.first
        }
    }

    /// Convenience builder with the two layouts the bulk of tests need: ABC and Russian.
    static func defaultRuEn(currentID: String = "com.apple.keylayout.ABC") -> FakeInputSources {
        FakeInputSources(
            layouts: [
                InputSource(id: "com.apple.keylayout.ABC", localizedName: "ABC", primaryLanguage: "en"),
                InputSource(id: "com.apple.keylayout.RussianWin", localizedName: "Russian", primaryLanguage: "ru")
            ],
            currentID: currentID
        )
    }

    func refresh() {
        // No-op: state is fully owned by this instance, never read from the system.
    }

    func keyboardLayouts() -> [InputSource] { layouts }

    func enabledLayouts() -> [InputSource] { layouts.filter(\.isEnabled) }

    @discardableResult
    func select(_ source: InputSource) -> OSStatus {
        selectedHistory.append(source.id)
        if let selectFailureStatus { return selectFailureStatus }
        if let match = layouts.first(where: { $0.id == source.id }) {
            current = match
        }
        return noErr
    }
}
