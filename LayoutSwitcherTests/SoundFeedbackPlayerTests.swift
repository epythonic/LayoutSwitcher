import Testing
@testable import LayoutSwitcher

@MainActor
struct SoundFeedbackPlayerTests {
    @Test func playCallsInjectedClosureWhenEnabled() {
        var playedKinds: [CorrectionFeedbackKind] = []
        let player = SoundFeedbackPlayer { kind in
            playedKinds.append(kind)
        }

        player.play(kind: .cupertino, isEnabled: true)

        #expect(playedKinds == [.cupertino])
    }

    @Test func playDoesNotCallInjectedClosureWhenDisabled() {
        var playedKinds: [CorrectionFeedbackKind] = []
        let player = SoundFeedbackPlayer { kind in
            playedKinds.append(kind)
        }

        player.play(kind: .layoutSwitch, isEnabled: false)

        #expect(playedKinds.isEmpty)
    }

    @Test func correctionFeedbackKindsExposeDistinctSignals() {
        let sounds = Set(CorrectionFeedbackKind.allCases.map(\.systemSoundName))
        let badges = Set(CorrectionFeedbackKind.allCases.map(\.visualBadge))

        #expect(sounds.count == CorrectionFeedbackKind.allCases.count)
        #expect(badges.count == CorrectionFeedbackKind.allCases.count)
        for kind in CorrectionFeedbackKind.allCases {
            #expect(!kind.localizedSummary(original: "a", corrected: "b").isEmpty)
        }
    }
}
