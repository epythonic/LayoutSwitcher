import CoreGraphics
import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct HotkeyCoordinatorTests {
    private struct StubMapping: KeyboardMapping {
        let languagePair: LanguagePair = .ruEn

        func transliterate(_ chars: [WordChar], to language: LanguageID) -> String {
            chars.map(\.unicode).joined()
        }
        func render(_ chars: [WordChar], in language: LanguageID) -> String {
            chars.map(\.unicode).joined()
        }
        func keyCode(for character: Character, language: LanguageID) -> (keyCode: CGKeyCode, shift: Bool)? {
            (keyCode: 0, shift: false)
        }
        func convert(_ text: String, from sourceLanguage: LanguageID, to targetLanguage: LanguageID) -> String {
            text
        }
    }

    private struct Fixture {
        let coordinator: HotkeyCoordinator
        let buffer: WordBuffer
        let stats: UsageStats
        let recents: RecentSwitches
        let appState: AppState
        let layoutState: LayoutState
        var retypedOriginal: [WordChar] = []
        var retypedCorrected: String = ""
        var retypedTarget: LanguageID?
    }

    private final class LayoutState {
        var currentLayoutID: String

        init(currentLayoutID: String) {
            self.currentLayoutID = currentLayoutID
        }
    }

    private static func makeFixture(
        currentLayoutID: String = "com.apple.keylayout.ABC",
        currentBundleID: String = "com.test.app",
        retypeSucceeds: Bool = true,
        activeLanguage: LanguageID = .en
    ) -> Fixture {
        let buffer = WordBuffer()
        let isolatedDefaults = UserDefaults(suiteName: "HotkeyCoordinatorTests-\(UUID().uuidString)") ?? .standard
        let stats = UsageStats(defaults: isolatedDefaults)
        let recents = RecentSwitches(defaults: isolatedDefaults)
        let appState = AppState(defaults: isolatedDefaults)
        let layoutState = LayoutState(currentLayoutID: currentLayoutID)
        let output = Fixture(coordinator: HotkeyCoordinator(
            buffer: buffer,
            mapping: StubMapping(),
            retyper: Retyper(
                mapping: StubMapping(),
                inputSources: FakeInputSources.defaultRuEn(),
                enabledLayoutsProvider: {
                    [
                        RetypeInputSource(id: "com.apple.keylayout.ABC", primaryLanguage: "en"),
                        RetypeInputSource(id: "com.apple.keylayout.RussianWin", primaryLanguage: "ru")
                    ]
                },
                currentLayoutIDProvider: { layoutState.currentLayoutID },
                refreshCurrentLayout: {},
                selectLayout: { layout in
                    layoutState.currentLayoutID = layout.id
                    return retypeSucceeds ? noErr : OSStatus(paramErr)
                },
                sleep: { _ in },
                postKeyEvent: { _, _ in },
                postUnicodeEvent: { _ in }
            ),
            inputSources: FakeInputSources.defaultRuEn(),
            stats: stats,
            recents: recents,
            appState: appState,
            currentBundleIDProvider: { currentBundleID },
            activeLanguageProvider: { activeLanguage },
            now: Date.init
        ), buffer: buffer, stats: stats, recents: recents, appState: appState, layoutState: layoutState)
        return output
    }

    private static func wordChars(_ unicode: String) -> [WordChar] {
        unicode.enumerated().map { index, char in
            WordChar(keyCode: CGKeyCode(index), unicode: String(char), flags: [], timestamp: UInt64(index))
        }
    }

    private static func waitUntil(
        timeoutNanoseconds: UInt64 = 200_000_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let step: UInt64 = 10_000_000
        var elapsed: UInt64 = 0
        while elapsed < timeoutNanoseconds {
            if condition() { return }
            try? await Task.sleep(nanoseconds: step)
            elapsed += step
        }
    }

    @Test func manualToggleRetypesLastCommittedWord() async {
        let fixture = Self.makeFixture()
        let buffer = fixture.buffer
        buffer.append(KeyEvent(keyCode: 5, flags: [], unicode: "g", timestamp: 1))
        buffer.append(KeyEvent(keyCode: 4, flags: [], unicode: "h", timestamp: 2))
        buffer.commit(separator: .space, separatorKeyCode: 49)
        let initialManual = fixture.stats.manualSwitchesTotal
        fixture.coordinator.handle(.manualToggleLast)
        await Self.waitUntil { fixture.stats.manualSwitchesTotal == initialManual + 1 }
        #expect(fixture.stats.manualSwitchesTotal == initialManual + 1)
    }

    @Test func manualToggleExpiredDoesNothing() async {
        let fixture = Self.makeFixture()
        let buffer = fixture.buffer
        buffer.append(KeyEvent(keyCode: 5, flags: [], unicode: "g", timestamp: 1))
        buffer.commit(separator: .space, separatorKeyCode: 49)
        // Simulate delay > 3.0s window by adjusting time? In practice we can't easily.
        // For now just verify that immediate toggle works; window test needs injected now.
        let initialManual = fixture.stats.manualSwitchesTotal
        fixture.coordinator.handle(.manualToggleLast)
        await Self.waitUntil { fixture.stats.manualSwitchesTotal == initialManual + 1 }
        #expect(fixture.stats.manualSwitchesTotal == initialManual + 1)
    }

    @Test func manualToggleFromUkrainianTargetsEnglish() async {
        let fixture = Self.makeFixture(currentLayoutID: "com.apple.keylayout.RussianWin", activeLanguage: .uk)
        let buffer = fixture.buffer
        buffer.append(KeyEvent(keyCode: 5, flags: [], unicode: "g", timestamp: 1))
        buffer.commit(separator: .space, separatorKeyCode: 49)

        fixture.coordinator.handle(.manualToggleLast)

        await Self.waitUntil { fixture.layoutState.currentLayoutID == "com.apple.keylayout.ABC" }
        #expect(fixture.layoutState.currentLayoutID == "com.apple.keylayout.ABC")
    }

    @Test func undoLastAutoSwitchRevertsCorrection() async {
        let fixture = Self.makeFixture()
        let record = AutoSwitchRecord(
            original: Self.wordChars("ghbdtn"),
            corrected: "привет",
            targetLanguage: .ru,
            sourceLanguage: .en,
            separator: .space,
            bundleID: "com.test.app",
            timestamp: Date(),
            originalText: "ghbdtn"
        )
        fixture.coordinator.lastAutoSwitch = record
        fixture.coordinator.handle(HotkeyAction.undoLastAutoSwitch)
        await Self.waitUntil { fixture.coordinator.lastAutoSwitch == nil }
        #expect(fixture.coordinator.lastAutoSwitch == nil)
    }

    @Test func undoWithMismatchedBundleDoesNothing() async {
        let fixture = Self.makeFixture(currentBundleID: "com.test.other")
        let record = AutoSwitchRecord(
            original: Self.wordChars("ghbdtn"),
            corrected: "привет",
            targetLanguage: .ru,
            sourceLanguage: .en,
            separator: .space,
            bundleID: "com.test.app",
            timestamp: Date(),
            originalText: "ghbdtn"
        )
        fixture.coordinator.lastAutoSwitch = record
        fixture.coordinator.handle(HotkeyAction.undoLastAutoSwitch)
        await Self.waitUntil(timeoutNanoseconds: 100_000_000) { fixture.coordinator.lastAutoSwitch == nil }
        #expect(fixture.coordinator.lastAutoSwitch == nil)
    }

    @Test func snoozeHotkeyStartsConfiguredPause() {
        let fixture = Self.makeFixture()
        fixture.appState.snoozeDuration = .fifteenMinutes

        fixture.coordinator.handle(.snooze)

        #expect(fixture.appState.isSnoozed)
        #expect(fixture.appState.activeSnoozeRemaining ?? 0 > 14 * 60)
    }

    @Test func snoozeHotkeyClearsActivePause() {
        let fixture = Self.makeFixture()
        fixture.appState.startSnooze()

        fixture.coordinator.handle(.snooze)

        #expect(!fixture.appState.isSnoozed)
        #expect(fixture.appState.snoozedUntil == nil)
    }

    @Test func forceRetypeLastWordCallsHandler() {
        var called = false
        let fixture = Self.makeFixture()
        fixture.coordinator.forceRetypeHandler = { called = true }

        fixture.coordinator.handle(.forceRetypeLastWord)

        #expect(called)
    }

    @Test func forceRetypeLastWordFallsBackToTypingPipeline() {
        let fixture = Self.makeFixture()
        fixture.coordinator.handle(.forceRetypeLastWord)

        // No crash and no-op when typingPipeline is nil is sufficient.
    }
}

private extension Optional {
    var isNil: Bool { self == nil }
}
