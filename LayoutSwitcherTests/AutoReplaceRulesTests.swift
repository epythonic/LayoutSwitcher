import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct AutoReplaceRulesTests {
    private static func makeDefaults(_ testName: String = #function) throws -> UserDefaults {
        let suiteName = "LayoutSwitcherTests.AutoReplace.\(testName)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func upsertAddsThenUpdatesByTrigger() throws {
        let rules = AutoReplaceRules(defaults: try Self.makeDefaults())

        rules.upsert(trigger: "тлф", replacement: "телефон")
        #expect(rules.replacement(for: "тлф") == "телефон")
        #expect(rules.rules.count == 1)

        rules.upsert(trigger: "тлф", replacement: "+7 999")
        #expect(rules.replacement(for: "тлф") == "+7 999")
        #expect(rules.rules.count == 1) // updated in place, not duplicated
    }

    @Test func ignoresEmptyTriggerOrReplacement() throws {
        let rules = AutoReplaceRules(defaults: try Self.makeDefaults())
        rules.upsert(trigger: "   ", replacement: "x")
        rules.upsert(trigger: "y", replacement: "")
        #expect(rules.rules.isEmpty)
    }

    @Test func removeDeletesMatchingTrigger() throws {
        let rules = AutoReplaceRules(defaults: try Self.makeDefaults())
        rules.upsert(trigger: "brb", replacement: "be right back")
        rules.remove(trigger: "brb")
        #expect(rules.replacement(for: "brb") == nil)
    }

    @Test func rulesPersistAcrossInstances() throws {
        let defaults = try Self.makeDefaults()
        let first = AutoReplaceRules(defaults: defaults)
        first.upsert(trigger: "omw", replacement: "on my way")
        first.isInlineEnabled = false

        let second = AutoReplaceRules(defaults: defaults)
        #expect(second.replacement(for: "omw") == "on my way")
        #expect(second.isInlineEnabled == false)
    }
}
