import CoreGraphics
import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct HotkeyRegistryTests {

    private static func makeDefaults(_ suffix: String) -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "com.gih.LayoutSwitcher.HotkeyRegistryTests.\(suffix)"
        let defaults = UserDefaults(suiteName: suiteName)
        #expect(defaults != nil)
        guard let defaults else { return (defaults: UserDefaults.standard, suiteName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults: defaults, suiteName: suiteName)
    }

    @Test func customBindingPersistsToDefaults() {
        let fixture = Self.makeDefaults("customBindingPersists")
        let defaults = fixture.defaults
        let suiteName = fixture.suiteName
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let registry = HotkeyRegistry(defaults: defaults)
        let customDefinition = HotkeyDefinition(keyCode: 42, modifiers: [.control, .option, .command, .shift])
        registry.setBinding(customDefinition, action: .manualToggleLast)

        let reloaded = HotkeyRegistry(defaults: defaults)
        #expect(reloaded.binding(for: .manualToggleLast) == customDefinition)
    }

    @Test func defaultBindingsContainManualToggleAndUndo() {
        let fixture = Self.makeDefaults("defaultBindingsContainManualToggleAndUndo")
        let defaults = fixture.defaults
        let suiteName = fixture.suiteName
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let registry = HotkeyRegistry(defaults: defaults)

        #expect(registry.bindings.values.contains(.manualToggleLast))
        #expect(registry.bindings.values.contains(.undoLastAutoSwitch))
        #expect(registry.bindings.values.contains(.convertSelection))
        #expect(registry.bindings.values.contains(.snooze))
        #expect(registry.bindings.values.contains(.forceRetypeLastWord))
    }

    @Test func defaultBindingsIncludeSnooze() {
        let fixture = Self.makeDefaults("defaultBindingsIncludeSnooze")
        let defaults = fixture.defaults
        let suiteName = fixture.suiteName
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let registry = HotkeyRegistry(defaults: defaults)
        #expect(registry.bindings.values.contains(.manualToggleLast))
        #expect(registry.bindings.values.contains(.undoLastAutoSwitch))
        #expect(registry.bindings.values.contains(.convertSelection))
        #expect(registry.bindings.values.contains(.snooze))
        #expect(registry.bindings.values.contains(.forceRetypeLastWord))
        
        let event = KeyEvent(
            kind: .keyDown,
            keyCode: 35,
            flags: [.maskControl, .maskAlternate, .maskCommand],
            unicode: "p",
            isAutoRepeat: false,
            sourcePID: 0,
            timestamp: 0
        )
        #expect(registry.match(event) == .snooze)
    }

    @Test func matchReturnsActionForKeyDownWithCorrectModifiers() {
        let fixture = Self.makeDefaults("matchReturnsAction")
        let defaults = fixture.defaults
        let suiteName = fixture.suiteName
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let registry = HotkeyRegistry(defaults: defaults)
        let event = KeyEvent(
            kind: .keyDown,
            keyCode: 42,
            flags: [.maskControl, .maskAlternate],
            unicode: "\\",
            isAutoRepeat: false,
            sourcePID: 0,
            timestamp: 0
        )
        #expect(registry.match(event) == .manualToggleLast)
    }

    @Test func matchReturnsNilForKeyUp() {
        let fixture = Self.makeDefaults("matchReturnsNilForKeyUp")
        let defaults = fixture.defaults
        let suiteName = fixture.suiteName
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let registry = HotkeyRegistry(defaults: defaults)
        let event = KeyEvent(
            kind: .flagsChanged,
            keyCode: 42,
            flags: [.maskControl, .maskAlternate],
            unicode: "\\",
            isAutoRepeat: false,
            sourcePID: 0,
            timestamp: 0
        )
        #expect(registry.match(event) == nil)
    }

    @Test func matchReturnsNilForWrongModifiers() {
        let fixture = Self.makeDefaults("matchReturnsNilForWrongModifiers")
        let defaults = fixture.defaults
        let suiteName = fixture.suiteName
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let registry = HotkeyRegistry(defaults: defaults)
        let event = KeyEvent(
            kind: .keyDown,
            keyCode: 42,
            flags: [.maskShift],
            unicode: "\\",
            isAutoRepeat: false,
            sourcePID: 0,
            timestamp: 0
        )
        #expect(registry.match(event) == nil)
    }

    @Test func setBindingReplacesOldDefinition() {
        let fixture = Self.makeDefaults("setBindingReplacesOldDefinition")
        let defaults = fixture.defaults
        let suiteName = fixture.suiteName
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let registry = HotkeyRegistry(defaults: defaults)
        let newDef = HotkeyDefinition(keyCode: 123, modifiers: [.command])
        registry.setBinding(newDef, action: .manualToggleLast)
        #expect(registry.bindings[newDef] == .manualToggleLast)
        // Old binding removed
        let oldDef = HotkeyDefinition(keyCode: 42, modifiers: [.control, .option])
        #expect(registry.bindings[oldDef] == nil)
    }

    @Test func setBindingReturnsConflictedActionAndUnassignsOld() {
        let fixture = Self.makeDefaults("setBindingReturnsConflictedAction")
        let defaults = fixture.defaults
        let suiteName = fixture.suiteName
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let registry = HotkeyRegistry(defaults: defaults)

        let conflictDef = HotkeyDefinition(keyCode: 6, modifiers: [.command, .option])
        let replacedAction = registry.setBinding(conflictDef, action: .manualToggleLast)
        #expect(replacedAction == .undoLastAutoSwitch)

        #expect(registry.binding(for: .manualToggleLast) == conflictDef)
        #expect(registry.binding(for: .undoLastAutoSwitch) == nil)
    }

    @Test func setBindingDoesNotReturnReplacedActionForSameAction() {
        let fixture = Self.makeDefaults("setBindingSameAction")
        let defaults = fixture.defaults
        let suiteName = fixture.suiteName
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let registry = HotkeyRegistry(defaults: defaults)

        let existingDef = HotkeyDefinition(keyCode: 42, modifiers: [.control, .option])
        let replacedAction = registry.setBinding(existingDef, action: .manualToggleLast)
        #expect(replacedAction == nil)
        #expect(registry.binding(for: .manualToggleLast) == existingDef)
    }

    @Test func setBindingConflictPersistsAcrossLaunches() {
        let fixture = Self.makeDefaults("setBindingConflictPersistsAcrossLaunches")
        let defaults = fixture.defaults
        let suiteName = fixture.suiteName
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let registry = HotkeyRegistry(defaults: defaults)
        let conflictDef = HotkeyDefinition(keyCode: 6, modifiers: [.command, .option])
        _ = registry.setBinding(conflictDef, action: .manualToggleLast)

        let reloaded = HotkeyRegistry(defaults: defaults)
        #expect(reloaded.binding(for: .manualToggleLast) == conflictDef)
        #expect(reloaded.binding(for: .undoLastAutoSwitch) == nil)
    }
}
