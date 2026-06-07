import Carbon.HIToolbox
import Testing
@testable import LayoutSwitcher

@MainActor
struct InputSourceManagerTests {
    private static func source(_ id: String, language: String = "en") -> InputSource {
        InputSource(id: id, localizedName: id, primaryLanguage: language)
    }

    private static func make(
        provider: @escaping @MainActor () -> InputSource?
    ) -> InputSourceManager {
        InputSourceManager(
            currentInputSourceProvider: provider,
            keyboardLayoutsProvider: { [] },
            selectInputSource: { _ in noErr },
            observeSystemChanges: { _ in nil },
            removeSystemChangeObserver: { _ in }
        )
    }

    @Test func reconcileUpdatesCurrentAndFiresOnChangeOnlyOnTransition() {
        final class Box { var value: InputSource? }
        let box = Box()
        box.value = Self.source("com.apple.keylayout.ABC")

        let manager = Self.make { box.value }
        #expect(manager.current?.id == "com.apple.keylayout.ABC") // loaded at init

        var changes: [String?] = []
        manager.onChange = { changes.append($0?.id) }

        // Reconcile with no underlying change must not fire callbacks.
        manager.reconcileCurrentInputSource()
        #expect(changes.isEmpty)

        // Simulate wake / hot-plug switching the selected source out from under us.
        box.value = Self.source("com.apple.keylayout.RussianWin", language: "ru")
        manager.reconcileCurrentInputSource()
        #expect(manager.current?.id == "com.apple.keylayout.RussianWin")
        #expect(changes == ["com.apple.keylayout.RussianWin"])
    }
}
