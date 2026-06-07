import Foundation
import Observation

/// One text auto-replacement: typing `trigger` as a whole word expands to `replacement`.
struct AutoReplaceRule: Hashable, Sendable, Identifiable {
    var id: String { trigger }
    let trigger: String
    let replacement: String
}

/// Persistent, ordered list of auto-replace rules backed by `UserDefaults`.
@MainActor
@Observable
final class AutoReplaceRules {
    private static let defaultsKey = "settings.autoReplaceRules"
    private static let triggerField = "trigger"
    private static let replacementField = "replacement"

    /// Whether inline auto-replace (expand on word boundary) is enabled.
    var isInlineEnabled: Bool {
        didSet { defaults.set(isInlineEnabled, forKey: Self.inlineEnabledKey) }
    }
    private static let inlineEnabledKey = "settings.autoReplaceInlineEnabled"

    private(set) var rules: [AutoReplaceRule]
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        self.isInlineEnabled = defaults.object(forKey: Self.inlineEnabledKey) as? Bool ?? true
        self.rules = Self.load(from: defaults)
    }

    /// Returns the replacement for an exact trigger match, if any.
    func replacement(for trigger: String) -> String? {
        rules.first(where: { $0.trigger == trigger })?.replacement
    }

    /// Adds a new rule or updates the replacement of an existing trigger.
    func upsert(trigger: String, replacement: String) {
        let trimmedTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTrigger.isEmpty, !replacement.isEmpty else { return }
        let rule = AutoReplaceRule(trigger: trimmedTrigger, replacement: replacement)
        if let index = rules.firstIndex(where: { $0.trigger == trimmedTrigger }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        persist()
    }

    /// Removes the rule with the given trigger, if present.
    func remove(trigger: String) {
        rules.removeAll { $0.trigger == trigger }
        persist()
    }

    private func persist() {
        let payload = rules.map { [Self.triggerField: $0.trigger, Self.replacementField: $0.replacement] }
        defaults.set(payload, forKey: Self.defaultsKey)
    }

    private static func load(from defaults: UserDefaults) -> [AutoReplaceRule] {
        guard let payload = defaults.array(forKey: Self.defaultsKey) as? [[String: String]] else {
            return []
        }
        return payload.compactMap { entry in
            guard let trigger = entry[triggerField], let replacement = entry[replacementField] else {
                return nil
            }
            return AutoReplaceRule(trigger: trigger, replacement: replacement)
        }
    }
}
