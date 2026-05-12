import CoreGraphics
import Foundation
import Observation

/// Supported user-triggered hotkey actions.
enum HotkeyAction: Hashable {
    case manualToggleLast
    case convertLastSentence
    case undoLastAutoSwitch
    case convertSelection
    case smartPaste
    case snooze
    case forceRetypeLastWord

    /// Ordered list used by settings and onboarding renderers.
    static let ordered: [HotkeyAction] = [
        .manualToggleLast,
        .convertLastSentence,
        .undoLastAutoSwitch,
        .convertSelection,
        .smartPaste,
        .snooze,
        .forceRetypeLastWord
    ]

    static let allActions: [HotkeyAction] = ordered

    /// Localized title shown in settings rows and onboarding.
    var localizedTitle: String {
        switch self {
        case .manualToggleLast:
            String(localized: "settings.hotkeys.manual-toggle.title")
        case .convertLastSentence:
            String(localized: "settings.hotkeys.convert-last-sentence.title")
        case .undoLastAutoSwitch:
            String(localized: "settings.hotkeys.undo-auto-switch.title")
        case .convertSelection:
            String(localized: "settings.hotkeys.convert-selection.title")
        case .smartPaste:
            String(localized: "settings.hotkeys.smart-paste.title")
        case .snooze:
            String(localized: "settings.hotkeys.snooze.title")
        case .forceRetypeLastWord:
            String(localized: "settings.hotkeys.force-retype-last-word.title")
        }
    }

    /// Localized subtitle shown in settings rows.
    var localizedSubtitle: String {
        switch self {
        case .manualToggleLast:
            String(localized: "settings.hotkeys.manual-toggle.subtitle")
        case .convertLastSentence:
            String(localized: "settings.hotkeys.convert-last-sentence.subtitle")
        case .undoLastAutoSwitch:
            String(localized: "settings.hotkeys.undo-auto-switch.subtitle")
        case .convertSelection:
            String(localized: "settings.hotkeys.convert-selection.subtitle")
        case .smartPaste:
            String(localized: "settings.hotkeys.smart-paste.subtitle")
        case .snooze:
            String(localized: "settings.hotkeys.snooze.subtitle")
        case .forceRetypeLastWord:
            String(localized: "settings.hotkeys.force-retype-last-word.subtitle")
        }
    }

    /// Stable key used for persistence payloads.
    var persistenceKey: String {
        switch self {
        case .manualToggleLast:
            return "manualToggleLast"
        case .convertLastSentence:
            return "convertLastSentence"
        case .undoLastAutoSwitch:
            return "undoLastAutoSwitch"
        case .convertSelection:
            return "convertSelection"
        case .smartPaste:
            return "smartPaste"
        case .snooze:
            return "snooze"
        case .forceRetypeLastWord:
            return "forceRetypeLastWord"
        }
    }

    /// Restores action from persisted storage key.
    init?(persistenceKey: String) {
        switch persistenceKey {
        case "manualToggleLast": self = .manualToggleLast
        case "convertLastSentence": self = .convertLastSentence
        case "undoLastAutoSwitch": self = .undoLastAutoSwitch
        case "convertSelection": self = .convertSelection
        case "smartPaste": self = .smartPaste
        case "snooze": self = .snooze
        case "forceRetypeLastWord": self = .forceRetypeLastWord
        default:
            return nil
        }
    }
}

/// Key + modifier combination that maps to one `HotkeyAction`.
struct HotkeyDefinition: Hashable {
    let keyCode: CGKeyCode
    let modifiers: ModifierMask

    /// Platform-agnostic modifier mask used for persisted / comparable hotkey definitions.
    struct ModifierMask: OptionSet, Hashable {
        let rawValue: UInt64
        static let control = ModifierMask(rawValue: 1 << 0)
        static let option  = ModifierMask(rawValue: 1 << 1)
        static let shift   = ModifierMask(rawValue: 1 << 2)
        static let command = ModifierMask(rawValue: 1 << 3)
    }
}

extension HotkeyDefinition.ModifierMask {
    /// Converts `CGEventFlags` to compact `ModifierMask` representation.
    static func from(_ flags: CGEventFlags) -> HotkeyDefinition.ModifierMask {
        var mask: HotkeyDefinition.ModifierMask = []
        if flags.contains(.maskControl)   { mask.insert(.control) }
        if flags.contains(.maskAlternate) { mask.insert(.option) }
        if flags.contains(.maskShift)     { mask.insert(.shift) }
        if flags.contains(.maskCommand)   { mask.insert(.command) }
        return mask
    }
}

extension HotkeyDefinition {
    /// Human-readable shortcut representation for UI labels.
    var displayText: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    private static func keyName(for keyCode: CGKeyCode) -> String {
        switch keyCode {
        case 6: return "Z"
        case 8: return "C"
        case 15: return "R"
        case 35: return "P"
        case 42: return "\\"
        case 36: return "↩"
        case 49: return "Space"
        case 53: return "Esc"
        default:
            return "k\(keyCode)"
        }
    }
}

/// Runtime registry of hotkey bindings with match/update operations.
@MainActor
@Observable
final class HotkeyRegistry {
    private static let defaultsKey = "settings.hotkeys.bindings"
    private static let boundPayloadKey = "bound"
    private static let keyCodePayloadKey = "keyCode"
    private static let modifiersPayloadKey = "modifiers"

    private(set) var bindings: [HotkeyDefinition: HotkeyAction]
    private let defaults: UserDefaults
    var onAction: ((HotkeyAction) -> Void)?
    /// Notifies subscribers (e.g. `CarbonHotkeyManager`) that bindings changed
    /// and should be re-registered with the OS.
    var onBindingsChanged: (() -> Void)?

    /// Returns supported hotkey definitions for the action, if any.
    func binding(for action: HotkeyAction) -> HotkeyDefinition? {
        bindings.first(where: { $0.value == action })?.key
    }

    /// Builds registry with default shortcut bindings.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.bindings = Self.loadBindings(from: defaults)
    }

    /// Default action bindings for a clean install.
    private static let defaultBindings: [HotkeyDefinition: HotkeyAction] = [
            // Control + Option + \ — manual toggle of the last word.
            HotkeyDefinition(keyCode: 42, modifiers: [.control, .option]): .manualToggleLast,
            // Control + Option + Shift + \ — convert the trailing sentence.
            HotkeyDefinition(keyCode: 42, modifiers: [.control, .option, .shift]): .convertLastSentence,
            // Command + Option + Z — undo the last automatic switch.
            HotkeyDefinition(keyCode: 6, modifiers: [.command, .option]): .undoLastAutoSwitch,
            // Control + Option + C — convert selected text.
            HotkeyDefinition(keyCode: 8, modifiers: [.control, .option]): .convertSelection,
            // Control + Option + Command + V — smart paste with layout alignment.
            HotkeyDefinition(keyCode: 9, modifiers: [.control, .option, .command]): .smartPaste,
            // Control + Option + Command + P — temporarily pause automatic switching.
            HotkeyDefinition(keyCode: 35, modifiers: [.control, .option, .command]): .snooze,
            // Control + Option + Command + R — force-retype last committed word.
            HotkeyDefinition(keyCode: 15, modifiers: [.control, .option, .command]): .forceRetypeLastWord
        ]

    /// Loads bindings from persistence and falls back to defaults.
    private static func loadBindings(from defaults: UserDefaults) -> [HotkeyDefinition: HotkeyAction] {
        guard let payload = defaults.dictionary(forKey: defaultsKey) as? [String: [String: Any]] else {
            return defaultBindings
        }

        var loaded: [HotkeyDefinition: HotkeyAction] = [:]
        var explicitlyUnbound: Set<HotkeyAction> = []
        for (actionKey, rawEntry) in payload {
            guard let action = HotkeyAction(persistenceKey: actionKey) else { continue }
            if let bound = rawEntry[Self.boundPayloadKey] as? Bool, !bound {
                explicitlyUnbound.insert(action)
                continue
            }
            guard let keyCodeValue = rawEntry[Self.keyCodePayloadKey],
                  let keyCode = Self.toUInt16(keyCodeValue),
                  let modifiersValue = rawEntry[Self.modifiersPayloadKey],
                  let modifiers = Self.toUInt64(modifiersValue) else {
                continue
            }
            let definition = HotkeyDefinition(
                keyCode: keyCode,
                modifiers: HotkeyDefinition.ModifierMask(rawValue: modifiers)
            )
            loaded[definition] = action
        }

        if loaded.isEmpty && explicitlyUnbound.isEmpty {
            return defaultBindings
        }
        return Self.merge(withDefaults: loaded, explicitUnbound: explicitlyUnbound)
    }

    /// Merges loaded bindings with defaults, keeping loaded bindings for known actions.
    private static func merge(
        withDefaults loaded: [HotkeyDefinition: HotkeyAction],
        explicitUnbound: Set<HotkeyAction>
    ) -> [HotkeyDefinition: HotkeyAction] {
        var merged = defaultBindings
        for (definition, action) in loaded {
            merged = merged.filter { $0.value != action && $0.key != definition }
            merged[definition] = action
        }

        for action in explicitUnbound {
            merged = merged.filter { $0.value != action }
        }

        return merged
    }

    /// Persists current bindings map to defaults.
    private func persistBindings() {
        var payload: [String: [String: Any]] = [:]
        for (definition, action) in bindings {
            payload[action.persistenceKey] = [
                Self.boundPayloadKey: true,
                Self.keyCodePayloadKey: Int(definition.keyCode),
                Self.modifiersPayloadKey: Int(definition.modifiers.rawValue)
            ]
        }

        for action in HotkeyAction.allActions where payload[action.persistenceKey] == nil {
            payload[action.persistenceKey] = [Self.boundPayloadKey: false]
        }

        defaults.set(payload, forKey: Self.defaultsKey)
    }

    /// Normalizes value from UserDefaults to `UInt16` safely.
    private static func toUInt16(_ value: Any) -> CGKeyCode? {
        guard let intValue = toInt(value) else { return nil }
        guard intValue >= 0, intValue <= Int(CGKeyCode.max) else { return nil }
        return CGKeyCode(intValue)
    }

    /// Normalizes value from UserDefaults to `UInt64` safely.
    private static func toUInt64(_ value: Any) -> UInt64? {
        guard let intValue = toInt(value) else { return nil }
        guard intValue >= 0 else { return nil }
        return UInt64(intValue)
    }

    /// Normalizes an `Any` payload value into Int.
    private static func toInt(_ value: Any) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        return value as? Int
    }

    /// Matches incoming event to configured action, if any.
    func match(_ event: KeyEvent) -> HotkeyAction? {
        guard case .keyDown = event.kind else { return nil }
        let mask = HotkeyDefinition.ModifierMask.from(event.flags)
        let def = HotkeyDefinition(keyCode: event.keyCode, modifiers: mask)
        return bindings[def]
    }

    /// Rebinds one action to a new definition.
    ///
    /// Returns previously assigned action if the chosen definition was already
    /// bound to another action.
    @discardableResult
    func setBinding(_ definition: HotkeyDefinition, action: HotkeyAction) -> HotkeyAction? {
        let conflictingAction = bindings[definition]
        bindings = bindings.filter { $0.value != action && $0.key != definition }
        bindings[definition] = action
        persistBindings()
        onBindingsChanged?()
        if let conflictingAction, conflictingAction != action {
            return conflictingAction
        }
        return nil
    }
}
