import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct ExclusionListTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ExclusionListTests-\(UUID().uuidString)") ?? .standard
    }

    @Test func firstRunSeedsRecommendedDefaults() {
        let defaults = makeDefaults()

        let exclusions = ExclusionList(defaults: defaults, localizedNameProvider: { _ in nil })

        #expect(exclusions.contains("com.apple.Terminal"))
        #expect(exclusions.contains("com.apple.Console"))
        #expect(exclusions.contains("com.apple.ActivityMonitor"))
        #expect(exclusions.contains("com.apple.ScriptEditor2"))
        #expect(exclusions.contains("GIH.LayoutSwitcher"))
        #expect(defaults.bool(forKey: "exclusions.defaultSeedApplied"))
        #expect(Set(defaults.array(forKey: "exclusions.bundleIDs") as? [String] ?? []) == ExclusionList.defaults)
    }

    @Test func userRemovedDefaultIsNotSeededAgain() {
        let defaults = makeDefaults()
        let exclusions = ExclusionList(defaults: defaults, localizedNameProvider: { _ in nil })

        exclusions.remove("com.apple.Terminal")
        let reloaded = ExclusionList(defaults: defaults, localizedNameProvider: { _ in nil })

        #expect(!reloaded.contains("com.apple.Terminal"))
        #expect(reloaded.contains("com.apple.Console"))
    }

    @Test func seedAppliedWithoutStoredListDoesNotReapplyDefaults() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "exclusions.defaultSeedApplied")

        let exclusions = ExclusionList(defaults: defaults, localizedNameProvider: { _ in nil })

        #expect(exclusions.bundleIDs.isEmpty)
        #expect((defaults.array(forKey: "exclusions.bundleIDs") as? [String]) == [])
    }

    @Test func legacyDefaultsKeyIsMigratedToNamespacedKey() {
        let defaults = makeDefaults()
        defaults.set(["com.example.Legacy"], forKey: "exclusionBundleIDs")

        let exclusions = ExclusionList(defaults: defaults, localizedNameProvider: { _ in nil })

        #expect(exclusions.contains("com.example.Legacy"))
        #expect(defaults.array(forKey: "exclusions.bundleIDs") as? [String] != nil)
    }

    @Test func persistRemovesLegacyDefaultsKey() {
        let defaults = makeDefaults()
        defaults.set(["com.example.Legacy"], forKey: "exclusionBundleIDs")
        let exclusions = ExclusionList(defaults: defaults, localizedNameProvider: { _ in nil })

        exclusions.add("com.example.New")

        #expect(defaults.object(forKey: "exclusionBundleIDs") == nil)
        #expect(exclusions.contains("com.example.New"))
    }
}
