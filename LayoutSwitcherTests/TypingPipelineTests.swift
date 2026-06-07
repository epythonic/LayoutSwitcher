import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import LayoutSwitcher

@MainActor
struct TypingPipelineTests {
    private struct NoopFocusedRoleProvider: FocusedRoleProviding {
        func focusedRole() -> String? { nil }
    }

    private static func makeFocusedAppObserver() -> FocusedAppObserver {
        FocusedAppObserver(
            roleProvider: NoopFocusedRoleProvider(),
            currentAppSnapshotProvider: { nil },
            observeWorkspaceActivation: { _ in nil },
            removeWorkspaceObserver: { _ in }
        )
    }

    private static func makeDefaults(_ testName: String = #function) throws -> UserDefaults {
        let suiteName = "TypingPipelineTests.\(testName)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private static func fixedID(_ byte: UInt8 = 1) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte))
    }

    @Test func autoSwitchRecordsOnlyAfterSuccessfulRetype() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: true)
        let initialWords = fixture.stats.wordsCommittedTotal
        let initialSwitches = fixture.stats.autoSwitchesTotal

        for event in [
            Self.key(5, "g"),
            Self.key(4, "h"),
            Self.key(11, "b"),
            Self.key(2, "d"),
            Self.key(17, "t"),
            Self.key(45, "n"),
            Self.key(49, " ")
        ] {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil { fixture.stats.autoSwitchesTotal == initialSwitches + 1 }

        #expect(fixture.stats.wordsCommittedTotal == initialWords + 1)
        #expect(fixture.stats.autoSwitchesTotal == initialSwitches + 1)
        #expect(fixture.recents.entries.first?.original == "ghbdtn")
        #expect(fixture.recents.entries.first?.corrected == "привет")
        #expect(fixture.output.selectedLayouts == ["com.apple.keylayout.RussianWin"])
        #expect(fixture.output.postedKeys.first == 51)
    }

    @Test func failedRetypeDoesNotRecordAutoSwitchOrRecent() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: false)
        let initialWords = fixture.stats.wordsCommittedTotal
        let initialSwitches = fixture.stats.autoSwitchesTotal

        for event in [
            Self.key(5, "g"),
            Self.key(4, "h"),
            Self.key(11, "b"),
            Self.key(2, "d"),
            Self.key(17, "t"),
            Self.key(45, "n"),
            Self.key(49, " ")
        ] {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil { !fixture.pipeline.isRetyping }

        #expect(fixture.stats.wordsCommittedTotal == initialWords + 1)
        #expect(fixture.stats.autoSwitchesTotal == initialSwitches)
        #expect(fixture.recents.entries.isEmpty)
        #expect(fixture.output.postedKeys.isEmpty)
    }

    @Test func repeatedIdenticalSingleWordIsSuppressedDuringCooldown() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: true)
        let initialSwitches = fixture.stats.autoSwitchesTotal
        let initialRecents = fixture.recents.entries.count

        let word = [
            Self.key(5, "g"),
            Self.key(4, "h"),
            Self.key(11, "b"),
            Self.key(2, "d"),
            Self.key(17, "t"),
            Self.key(45, "n"),
            Self.key(49, " ")
        ]
        for event in word {
            fixture.pipeline.handle(event)
        }
        await Self.waitUntil { fixture.stats.autoSwitchesTotal == initialSwitches + 1 }
        let postedKeyCount = fixture.output.postedKeys.count

        for event in word {
            fixture.pipeline.handle(event)
        }
        await Self.waitForAsyncWorkWindow(nanoseconds: 250_000_000)

        #expect(fixture.stats.autoSwitchesTotal == initialSwitches + 1)
        #expect(fixture.recents.entries.count == initialRecents + 1)
        #expect(fixture.output.postedKeys.count == postedKeyCount)
    }

    @Test func enterSeparatorCommitsButSuppressesAutoSwitch() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: true)
        let initialWords = fixture.stats.wordsCommittedTotal
        let initialSwitches = fixture.stats.autoSwitchesTotal

        for event in [
            Self.key(5, "g"),
            Self.key(4, "h"),
            Self.key(11, "b"),
            Self.key(2, "d"),
            Self.key(17, "t"),
            Self.key(45, "n"),
            Self.key(36, "\n")
        ] {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil { fixture.stats.wordsCommittedTotal == initialWords + 1 }

        #expect(fixture.stats.autoSwitchesTotal == initialSwitches)
        #expect(fixture.recents.entries.isEmpty)
        #expect(fixture.output.postedKeys.isEmpty)
    }

    @Test func disabledPipelineDoesNotCommitOrRetype() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: true)
        fixture.appState.isEnabled = false
        let initialWords = fixture.stats.wordsCommittedTotal
        let initialSwitches = fixture.stats.autoSwitchesTotal

        for event in [
            Self.key(5, "g"),
            Self.key(4, "h"),
            Self.key(11, "b"),
            Self.key(2, "d"),
            Self.key(17, "t"),
            Self.key(45, "n"),
            Self.key(49, " ")
        ] {
            fixture.pipeline.handle(event)
        }

        await Self.waitForAsyncWorkWindow(nanoseconds: 20_000_000)

        #expect(fixture.stats.wordsCommittedTotal == initialWords)
        #expect(fixture.stats.autoSwitchesTotal == initialSwitches)
        #expect(fixture.recents.entries.isEmpty)
        #expect(fixture.output.postedKeys.isEmpty)
    }

    @Test func disabledLanguageDirectionSuppressesCrossLayoutSwitch() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: true)
        fixture.appState.setLanguageDirection(.enToRu, isEnabled: false)
        let initialSwitches = fixture.stats.autoSwitchesTotal

        for event in [
            Self.key(5, "g"),
            Self.key(4, "h"),
            Self.key(11, "b"),
            Self.key(2, "d"),
            Self.key(17, "t"),
            Self.key(45, "n"),
            Self.key(49, " ")
        ] {
            fixture.pipeline.handle(event)
        }

        await Self.waitForAsyncWorkWindow(nanoseconds: 250_000_000)

        #expect(fixture.stats.autoSwitchesTotal == initialSwitches)
        #expect(fixture.recents.entries.isEmpty)
        #expect(fixture.output.selectedLayouts.isEmpty)
        #expect(fixture.output.postedKeys.isEmpty)
    }

    @Test func disabledLanguageDirectionKeepsSameLanguageTypoCorrection() async throws {
        let fixture = try Self.makeFixture(
            retypeSucceeds: true,
            enabledLayouts: [
                RetypeInputSource(id: "com.apple.keylayout.ABC", primaryLanguage: "en"),
                RetypeInputSource(id: "com.apple.keylayout.RussianWin", primaryLanguage: "ru")
            ]
        )
        fixture.appState.setLanguageDirection(.enToRu, isEnabled: false)
        fixture.appState.correctCommonTypos = true

        for event in try Self.wordEvents("bokk", language: .en) {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil {
            fixture.recents.entries.first?.corrected == "book"
        }

        #expect(fixture.recents.entries.first?.original == "bokk")
        #expect(fixture.recents.entries.first?.corrected == "book")
        #expect(fixture.output.selectedLayouts.isEmpty)
        #expect(fixture.output.playedFeedback == [.cupertino])
    }

    @Test func unavailableLanguageDirectionDoesNotStealInstalledTarget() async throws {
        let detector = LayoutDetector(
            mapping: RuEnQwertyMapping(),
            dictionaries: [
                .en: InMemoryDictionary(language: .en, words: ["hello"]),
                .ru: InMemoryDictionary(language: .ru, words: ["привет"]),
                .uk: InMemoryDictionary(language: .uk, words: ["привіт"])
            ],
            ngrams: [
                .en: NGramModels.english(),
                .ru: NGramModels.russian(),
                .uk: NGramModels.ukrainian()
            ],
            languageScorer: FixedScoreScorer(scores: [
                .en: LanguageScore(naturalLanguageProbability: nil, nGramScore: -1.0),
                .ru: LanguageScore(naturalLanguageProbability: nil, nGramScore: 0.1),
                .uk: LanguageScore(naturalLanguageProbability: nil, nGramScore: 1.0)
            ]),
            thresholds: .default
        )
        let fixture = try Self.makeFixture(
            retypeSucceeds: true,
            enabledLayouts: [
                RetypeInputSource(id: "com.apple.keylayout.ABC", primaryLanguage: "en"),
                RetypeInputSource(id: "com.apple.keylayout.RussianWin", primaryLanguage: "ru")
            ],
            detector: detector
        )

        for event in try Self.wordEvents("ghbdtn", language: .en) {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil {
            fixture.recents.entries.first?.corrected == "привет"
        }

        #expect(fixture.recents.entries.first?.original == "ghbdtn")
        #expect(fixture.recents.entries.first?.corrected == "привет")
        #expect(fixture.output.selectedLayouts == ["com.apple.keylayout.RussianWin"])
    }

    @Test func inactiveInstalledLanguagePairDoesNotParticipate() async throws {
        let detector = LayoutDetector(
            mapping: RuEnQwertyMapping(),
            dictionaries: [
                .en: InMemoryDictionary(language: .en, words: ["hello"]),
                .ru: InMemoryDictionary(language: .ru, words: ["привет"]),
                .uk: InMemoryDictionary(language: .uk, words: ["привіт"])
            ],
            ngrams: [
                .en: NGramModels.english(),
                .ru: NGramModels.russian(),
                .uk: NGramModels.ukrainian()
            ],
            languageScorer: FixedScoreScorer(scores: [
                .en: LanguageScore(naturalLanguageProbability: nil, nGramScore: -1.0),
                .ru: LanguageScore(naturalLanguageProbability: nil, nGramScore: 0.1),
                .uk: LanguageScore(naturalLanguageProbability: nil, nGramScore: 1.0)
            ]),
            thresholds: .default
        )
        let inputSources = FakeInputSources(layouts: [
            InputSource(id: "com.apple.keylayout.ABC", localizedName: "ABC", primaryLanguage: "en"),
            InputSource(id: "com.apple.keylayout.RussianWin", localizedName: "Russian", primaryLanguage: "ru"),
            InputSource(id: "com.apple.keylayout.Ukrainian-PC", localizedName: "Ukrainian", primaryLanguage: "uk")
        ])
        let fixture = try Self.makeFixture(
            retypeSucceeds: true,
            enabledLayouts: [
                RetypeInputSource(id: "com.apple.keylayout.ABC", primaryLanguage: "en"),
                RetypeInputSource(id: "com.apple.keylayout.RussianWin", primaryLanguage: "ru"),
                RetypeInputSource(id: "com.apple.keylayout.Ukrainian-PC", primaryLanguage: "uk")
            ],
            detector: detector,
            inputSources: inputSources
        )
        fixture.appState.setActiveLanguagePair(.ruEn)

        for event in try Self.wordEvents("ghbdtn", language: .en) {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil {
            fixture.recents.entries.first?.corrected == "привет"
        }

        #expect(fixture.recents.entries.first?.original == "ghbdtn")
        #expect(fixture.recents.entries.first?.corrected == "привет")
        #expect(fixture.output.selectedLayouts == ["com.apple.keylayout.RussianWin"])
    }

    @Test func inactiveUkrainianVisibleCandidateFallsBackToRussianPair() async throws {
        let detector = LayoutDetector(
            mapping: RuEnQwertyMapping(),
            dictionaries: [
                .en: EmbeddedDictionaries.english(),
                .ru: EmbeddedDictionaries.russian(),
                .uk: EmbeddedDictionaries.ukrainian(),
                .ro: EmbeddedDictionaries.romanian()
            ],
            ngrams: [
                .en: NGramModels.english(),
                .ru: NGramModels.russian(),
                .uk: NGramModels.ukrainian(),
                .ro: NGramModels.romanian()
            ],
            romanianDiacriticResolver: RomanianDiacriticResolver(words: EmbeddedDictionaries.romanian().allWords),
            russianYoResolver: RussianYoResolver(words: ["ёжик", "все", "всё"]),
            spellingSuggestionProvider: FixedSuggestionProvider(suggestionsByWord: [:]),
            thresholds: .default
        )
        let inputSources = FakeInputSources(layouts: [
            InputSource(id: "com.apple.keylayout.ABC", localizedName: "ABC", primaryLanguage: "en"),
            InputSource(id: "com.apple.keylayout.RussianWin", localizedName: "Russian", primaryLanguage: "ru"),
            InputSource(id: "com.apple.keylayout.Ukrainian-PC", localizedName: "Ukrainian", primaryLanguage: "uk")
        ])
        let fixture = try Self.makeFixture(
            retypeSucceeds: true,
            enabledLayouts: [
                RetypeInputSource(id: "com.apple.keylayout.ABC", primaryLanguage: "en"),
                RetypeInputSource(id: "com.apple.keylayout.RussianWin", primaryLanguage: "ru"),
                RetypeInputSource(id: "com.apple.keylayout.Ukrainian-PC", primaryLanguage: "uk")
            ],
            detector: detector,
            inputSources: inputSources
        )
        fixture.appState.setActiveLanguagePair(.ruEn)

        for event in try Self.wordEvents("ghbdtn", language: .en) {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil {
            fixture.recents.entries.first?.corrected == "привет"
        }

        #expect(fixture.recents.entries.first?.original == "ghbdtn")
        #expect(fixture.recents.entries.first?.corrected == "привет")
        #expect(fixture.output.selectedLayouts == ["com.apple.keylayout.RussianWin"])
    }

    @Test func duplicateLetterToggleControlsPipelineCorrection() async throws {
        let disabled = try Self.makeFixture(
            retypeSucceeds: true,
            enabledLayouts: [
                RetypeInputSource(id: "com.apple.keylayout.ABC", primaryLanguage: "en"),
                RetypeInputSource(id: "com.apple.keylayout.RussianWin", primaryLanguage: "ru")
            ]
        )
        for event in try Self.wordEvents("helloo", language: .en) {
            disabled.pipeline.handle(event)
        }
        await Self.waitForAsyncWorkWindow(nanoseconds: 50_000_000)
        #expect(disabled.recents.entries.isEmpty)

        let enabled = try Self.makeFixture(
            retypeSucceeds: true,
            enabledLayouts: [
                RetypeInputSource(id: "com.apple.keylayout.ABC", primaryLanguage: "en"),
                RetypeInputSource(id: "com.apple.keylayout.RussianWin", primaryLanguage: "ru")
            ]
        )
        enabled.appState.correctDuplicateLetters = true
        for event in try Self.wordEvents("helloo", language: .en) {
            enabled.pipeline.handle(event)
        }

        await Self.waitUntil {
            enabled.recents.entries.first?.corrected == "hello"
        }
        #expect(enabled.recents.entries.first?.original == "helloo")
        #expect(enabled.recents.entries.first?.corrected == "hello")
    }

    @Test func visibleTextCorrectionSurvivesStaleInputSourceSnapshot() async throws {
        let fixture = try Self.makeFixture(
            retypeSucceeds: true,
            initialLayoutID: "com.apple.keylayout.RussianWin",
            enabledLayouts: [
                RetypeInputSource(id: "com.apple.keylayout.ABC", primaryLanguage: "en"),
                RetypeInputSource(id: "com.apple.keylayout.RussianWin", primaryLanguage: "ru")
            ]
        )
        fixture.appState.correctDuplicateLetters = true

        for event in try Self.wordEvents("helloo", language: .en) {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil {
            fixture.recents.entries.first?.corrected == "hello"
        }
        #expect(fixture.recents.entries.first?.original == "helloo")
        #expect(fixture.recents.entries.first?.corrected == "hello")
        #expect(fixture.output.playedFeedback == [.duplicateLetter])
        #expect(fixture.output.visualFeedback == [.duplicateLetter])
    }

    @Test func doubleCapitalToggleControlsPipelineCorrection() async throws {
        let disabled = try Self.makeFixture(
            retypeSucceeds: true,
            initialLayoutID: "com.apple.keylayout.RussianWin"
        )
        for event in try Self.wordEvents("ПРивет", language: .ru) {
            disabled.pipeline.handle(event)
        }
        await Self.waitForAsyncWorkWindow(nanoseconds: 50_000_000)
        #expect(disabled.recents.entries.isEmpty)

        let enabled = try Self.makeFixture(
            retypeSucceeds: true,
            initialLayoutID: "com.apple.keylayout.RussianWin"
        )
        enabled.appState.correctDoubleCapitals = true
        for event in try Self.wordEvents("ПРивет", language: .ru) {
            enabled.pipeline.handle(event)
        }

        await Self.waitUntil {
            enabled.recents.entries.first?.corrected == "Привет"
        }
        #expect(enabled.recents.entries.first?.original == "ПРивет")
        #expect(enabled.recents.entries.first?.corrected == "Привет")
    }

    @Test func duplicateLetterAndDoubleCapitalCorrectionsCompose() async throws {
        let fixture = try Self.makeFixture(
            retypeSucceeds: true,
            enabledLayouts: [
                RetypeInputSource(id: "com.apple.keylayout.ABC", primaryLanguage: "en"),
                RetypeInputSource(id: "com.apple.keylayout.RussianWin", primaryLanguage: "ru")
            ]
        )
        fixture.appState.correctDuplicateLetters = true
        fixture.appState.correctDoubleCapitals = true

        for event in try Self.wordEvents("HElloo", language: .en) {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil {
            fixture.recents.entries.first?.corrected == "Hello"
        }
        #expect(fixture.recents.entries.first?.original == "HElloo")
        #expect(fixture.recents.entries.first?.corrected == "Hello")
    }

    @Test func russianYoToggleControlsPipelineCorrection() async throws {
        let disabled = try Self.makeFixture(
            retypeSucceeds: true,
            initialLayoutID: "com.apple.keylayout.RussianWin"
        )
        for event in try Self.wordEvents("ежик", language: .ru) {
            disabled.pipeline.handle(event)
        }
        await Self.waitForAsyncWorkWindow(nanoseconds: 50_000_000)
        #expect(disabled.recents.entries.isEmpty)

        let enabled = try Self.makeFixture(
            retypeSucceeds: true,
            initialLayoutID: "com.apple.keylayout.RussianWin"
        )
        enabled.appState.autoAddRussianYo = true
        for event in try Self.wordEvents("ежик", language: .ru) {
            enabled.pipeline.handle(event)
        }

        await Self.waitUntil {
            enabled.recents.entries.first?.corrected == "ёжик"
        }
        #expect(enabled.recents.entries.first?.original == "ежик")
        #expect(enabled.recents.entries.first?.corrected == "ёжик")
    }

    @Test func russianYoUsesRenderedKeycodesWhenEventUnicodeIsLatin() async throws {
        let fixture = try Self.makeFixture(
            retypeSucceeds: true,
            initialLayoutID: "com.apple.keylayout.ABC"
        )
        fixture.appState.autoAddRussianYo = true

        for event in [
            Self.key(17, "t"),
            Self.key(41, ";"),
            Self.key(11, "b"),
            Self.key(15, "r"),
            Self.key(49, " ")
        ] {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil {
            fixture.recents.entries.first?.corrected == "ёжик"
        }
        #expect(fixture.recents.entries.first?.original == "ежик")
        #expect(fixture.recents.entries.first?.corrected == "ёжик")
    }

    @Test func cupertinoToggleControlsPipelineCorrectionAndFeedback() async throws {
        let disabled = try Self.makeFixture(
            retypeSucceeds: true,
            enabledLayouts: [
                RetypeInputSource(id: "com.apple.keylayout.ABC", primaryLanguage: "en")
            ]
        )
        for event in try Self.wordEvents("hellp", language: .en) {
            disabled.pipeline.handle(event)
        }
        await Self.waitForAsyncWorkWindow(nanoseconds: 50_000_000)
        #expect(disabled.recents.entries.isEmpty)

        let enabled = try Self.makeFixture(
            retypeSucceeds: true,
            enabledLayouts: [
                RetypeInputSource(id: "com.apple.keylayout.ABC", primaryLanguage: "en")
            ]
        )
        enabled.appState.correctCommonTypos = true
        for event in try Self.wordEvents("hellp", language: .en) {
            enabled.pipeline.handle(event)
        }

        await Self.waitUntil {
            enabled.recents.entries.first?.corrected == "hello"
        }
        #expect(enabled.recents.entries.first?.original == "hellp")
        #expect(enabled.recents.entries.first?.corrected == "hello")
        #expect(enabled.output.playedFeedback == [.cupertino])
        #expect(enabled.output.visualFeedback == [.cupertino])
    }

    @Test func visibleTypoCorrectionDoesNotOverrideStrongWrongLayoutSwitch() async throws {
        let fixture = try Self.makeFixture(
            retypeSucceeds: true,
            initialLayoutID: "com.apple.keylayout.RussianWin",
            enabledLayouts: [
                RetypeInputSource(id: "com.apple.keylayout.ABC", primaryLanguage: "en"),
                RetypeInputSource(id: "com.apple.keylayout.RussianWin", primaryLanguage: "ru")
            ]
        )
        fixture.appState.correctCommonTypos = true

        for event in try Self.wordEvents("руддщ", language: .ru) {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil {
            fixture.recents.entries.first?.corrected == "hello"
        }
        #expect(fixture.recents.entries.first?.original == "руддщ")
        #expect(fixture.recents.entries.first?.corrected == "hello")
        #expect(fixture.output.selectedLayouts == ["com.apple.keylayout.ABC"])
    }

    @Test func renderedCupertinoCorrectionBeatsActiveLanguageSuggestion() async throws {
        let fixture = try Self.makeFixture(
            retypeSucceeds: true,
            initialLayoutID: "com.apple.keylayout.RussianWin",
            enabledLayouts: [
                RetypeInputSource(id: "com.apple.keylayout.ABC", primaryLanguage: "en"),
                RetypeInputSource(id: "com.apple.keylayout.RussianWin", primaryLanguage: "ru")
            ]
        )
        fixture.appState.correctCommonTypos = true

        for event in try Self.wordEvents("ищлл", language: .ru) {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil {
            fixture.recents.entries.first?.corrected == "book"
        }
        #expect(fixture.recents.entries.first?.original == "ищлл")
        #expect(fixture.recents.entries.first?.corrected == "book")
        #expect(fixture.output.selectedLayouts == ["com.apple.keylayout.ABC"])
        #expect(fixture.output.playedFeedback == [.cupertino])
    }

    @Test func staleEnglishSnapshotPrefersRenderedCupertinoOverVisibleRussianSuggestion() async throws {
        let fixture = try Self.makeFixture(
            retypeSucceeds: true,
            initialLayoutID: "com.apple.keylayout.ABC",
            enabledLayouts: [
                RetypeInputSource(id: "com.apple.keylayout.ABC", primaryLanguage: "en"),
                RetypeInputSource(id: "com.apple.keylayout.RussianWin", primaryLanguage: "ru")
            ]
        )
        fixture.appState.correctCommonTypos = true

        for event in try Self.wordEvents("ищлл", language: .ru) {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil {
            fixture.recents.entries.first?.corrected == "book"
        }
        #expect(fixture.recents.entries.first?.original == "ищлл")
        #expect(fixture.recents.entries.first?.corrected == "book")
        #expect(fixture.output.selectedLayouts.isEmpty)
        #expect(fixture.output.playedFeedback == [.cupertino])
    }

    @Test func staleEnglishSnapshotPrefersRenderedDictionaryWordOverVisibleRussianSuggestion() async throws {
        let fixture = try Self.makeFixture(
            retypeSucceeds: true,
            initialLayoutID: "com.apple.keylayout.ABC",
            enabledLayouts: [
                RetypeInputSource(id: "com.apple.keylayout.ABC", primaryLanguage: "en"),
                RetypeInputSource(id: "com.apple.keylayout.RussianWin", primaryLanguage: "ru")
            ]
        )
        fixture.appState.correctCommonTypos = true

        for event in try Self.wordEvents("руддщ", language: .ru) {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil {
            fixture.recents.entries.first?.corrected == "hello"
        }
        #expect(fixture.recents.entries.first?.original == "руддщ")
        #expect(fixture.recents.entries.first?.corrected == "hello")
        #expect(fixture.output.selectedLayouts.isEmpty)
        #expect(fixture.output.playedFeedback == [.layoutSwitch])
    }

    @Test func visibleEnglishCupertinoBeatsRenderedRussianSuggestionWhenActiveSnapshotIsRussian() async throws {
        let fixture = try Self.makeFixture(
            retypeSucceeds: true,
            initialLayoutID: "com.apple.keylayout.RussianWin",
            enabledLayouts: Self.multilingualRetypeSources()
        )
        fixture.appState.correctCommonTypos = true

        for event in try Self.wordEvents("bokk", language: .en) {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil {
            fixture.recents.entries.first?.corrected == "book"
        }
        #expect(fixture.recents.entries.first?.original == "bokk")
        #expect(fixture.recents.entries.first?.corrected == "book")
        #expect(fixture.output.selectedLayouts == ["com.apple.keylayout.ABC"])
        #expect(fixture.output.playedFeedback == [.cupertino])
    }

    @Test func visibleEnglishCupertinoBeatsRussianSuggestionWhenActiveSnapshotIsEnglish() async throws {
        let fixture = try Self.makeFixture(
            retypeSucceeds: true,
            initialLayoutID: "com.apple.keylayout.ABC",
            enabledLayouts: Self.multilingualRetypeSources()
        )
        fixture.appState.correctCommonTypos = true

        for event in try Self.wordEvents("bokk", language: .en) {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil {
            fixture.recents.entries.first?.corrected == "book"
        }
        #expect(fixture.recents.entries.first?.original == "bokk")
        #expect(fixture.recents.entries.first?.corrected == "book")
        #expect(fixture.output.selectedLayouts.isEmpty)
        #expect(fixture.output.playedFeedback == [.cupertino])
    }

    @Test func visibleRussianDictionaryWordBeatsRenderedEnglishWhenActiveSnapshotIsEnglish() async throws {
        let fixture = try Self.makeFixture(
            retypeSucceeds: true,
            initialLayoutID: "com.apple.keylayout.ABC",
            enabledLayouts: Self.multilingualRetypeSources()
        )
        fixture.appState.correctCommonTypos = true

        for event in try Self.wordEvents("мир", language: .ru) {
            fixture.pipeline.handle(event)
        }

        await Self.waitForAsyncWorkWindow(nanoseconds: 50_000_000)

        #expect(fixture.recents.entries.isEmpty)
        #expect(fixture.output.selectedLayouts.isEmpty)
        #expect(fixture.output.postedKeys.isEmpty)
        #expect(fixture.output.postedUnicode.isEmpty)
    }

    @Test func visibleEnglishDoubleCapitalBeatsRenderedRussianSuggestionWhenActiveSnapshotIsRussian() async throws {
        let fixture = try Self.makeFixture(
            retypeSucceeds: true,
            initialLayoutID: "com.apple.keylayout.RussianWin",
            enabledLayouts: Self.multilingualRetypeSources()
        )
        fixture.appState.correctDoubleCapitals = true

        for event in try Self.wordEvents("HEllo", language: .en) {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil {
            fixture.recents.entries.first?.corrected == "Hello"
        }
        #expect(fixture.recents.entries.first?.original == "HEllo")
        #expect(fixture.recents.entries.first?.corrected == "Hello")
        #expect(fixture.output.selectedLayouts == ["com.apple.keylayout.ABC"])
        #expect(fixture.output.playedFeedback == [.doubleCapital])
    }

    @Test func visibleEnglishDoubleCapitalBeatsRussianSuggestionWhenActiveSnapshotIsEnglish() async throws {
        let fixture = try Self.makeFixture(
            retypeSucceeds: true,
            initialLayoutID: "com.apple.keylayout.ABC",
            enabledLayouts: Self.multilingualRetypeSources()
        )
        fixture.appState.correctDoubleCapitals = true

        for event in try Self.wordEvents("HEllo", language: .en) {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil {
            fixture.recents.entries.first?.corrected == "Hello"
        }
        #expect(fixture.recents.entries.first?.original == "HEllo")
        #expect(fixture.recents.entries.first?.corrected == "Hello")
        #expect(fixture.output.selectedLayouts.isEmpty)
        #expect(fixture.output.playedFeedback == [.doubleCapital])
    }

    @Test func visibleRomanianDuplicateLetterBeatsRenderedRussianSuggestionWhenActiveSnapshotIsRussian() async throws {
        let fixture = try Self.makeFixture(
            retypeSucceeds: true,
            initialLayoutID: "com.apple.keylayout.RussianWin",
            enabledLayouts: Self.multilingualRetypeSources()
        )
        fixture.appState.setActiveLanguagePair(.roEn)
        fixture.appState.correctDuplicateLetters = true

        for event in try Self.wordEvents("salutt", language: .ro) {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil {
            fixture.recents.entries.first?.corrected == "salut"
        }
        #expect(fixture.recents.entries.first?.original == "salutt")
        #expect(fixture.recents.entries.first?.corrected == "salut")
        #expect(fixture.output.selectedLayouts == ["com.apple.keylayout.Romanian-Standard"])
        #expect(fixture.output.playedFeedback == [.duplicateLetter])
    }

    @Test func visibleRomanianDoubleCapitalBeatsRenderedRussianSuggestionWhenActiveSnapshotIsRussian() async throws {
        let fixture = try Self.makeFixture(
            retypeSucceeds: true,
            initialLayoutID: "com.apple.keylayout.RussianWin",
            enabledLayouts: Self.multilingualRetypeSources()
        )
        fixture.appState.setActiveLanguagePair(.roEn)
        fixture.appState.correctDoubleCapitals = true

        for event in try Self.wordEvents("SAlut", language: .ro) {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil {
            fixture.recents.entries.first?.corrected == "Salut"
        }
        #expect(fixture.recents.entries.first?.original == "SAlut")
        #expect(fixture.recents.entries.first?.corrected == "Salut")
        #expect(fixture.output.selectedLayouts == ["com.apple.keylayout.Romanian-Standard"])
        #expect(fixture.output.playedFeedback == [.doubleCapital])
    }

    @Test func inactiveLanguagePairSuppressesRomanianSameLanguageCorrection() async throws {
        let inputSources = FakeInputSources(
            layouts: [
                InputSource(id: "com.apple.keylayout.ABC", localizedName: "ABC", primaryLanguage: "en"),
                InputSource(id: "com.apple.keylayout.RussianWin", localizedName: "Russian", primaryLanguage: "ru"),
                InputSource(id: "com.apple.keylayout.Romanian-Standard", localizedName: "Romanian", primaryLanguage: "ro")
            ],
            currentID: "com.apple.keylayout.Romanian-Standard"
        )
        let fixture = try Self.makeFixture(
            retypeSucceeds: true,
            initialLayoutID: "com.apple.keylayout.Romanian-Standard",
            enabledLayouts: Self.multilingualRetypeSources(),
            inputSources: inputSources
        )
        fixture.appState.setActiveLanguagePair(.ruEn)
        fixture.appState.correctCommonTypos = true

        for event in try Self.wordEvents("vbh", language: .en) {
            fixture.pipeline.handle(event)
        }

        await Self.waitForAsyncWorkWindow(nanoseconds: 50_000_000)
        #expect(fixture.recents.entries.isEmpty)
        #expect(fixture.output.selectedLayouts.isEmpty)
        #expect(fixture.output.playedFeedback.isEmpty)
    }

    @Test func pendingRussianSequenceCanAbsorbVisibleEnglishAcronymWithRussianCorrection() async throws {
        let fixture = try Self.makeFixture(
            retypeSucceeds: true,
            initialLayoutID: "com.apple.keylayout.ABC",
            enabledLayouts: Self.multilingualRetypeSources()
        )
        fixture.appState.correctCommonTypos = true

        for event in try Self.wordEvents("Pfrekxbk", language: .en) {
            fixture.pipeline.handle(event)
        }
        for event in try Self.wordEvents("tbh", language: .en) {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil {
            fixture.recents.entries.first?.corrected == "Заключил мир"
        }
        #expect(fixture.recents.entries.first?.original == "Pfrekxbk tbh")
        #expect(fixture.recents.entries.first?.corrected == "Заключил мир")
        #expect(fixture.output.selectedLayouts == ["com.apple.keylayout.RussianWin"])
    }

    @Test func recentRussianCorrectionContextCanFixFollowingVisibleEnglishAcronymAfterFlush() async throws {
        let fixture = try Self.makeFixture(
            retypeSucceeds: true,
            initialLayoutID: "com.apple.keylayout.ABC",
            enabledLayouts: Self.multilingualRetypeSources()
        )
        fixture.appState.correctCommonTypos = true

        for event in try Self.wordEvents("Pfrekxbk", language: .en) {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil {
            fixture.recents.entries.first?.corrected == "Заключил"
        }

        for event in try Self.wordEvents("tbh", language: .en) {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil {
            fixture.recents.entries.first?.corrected == "мир"
        }
        #expect(fixture.recents.entries.first?.original == "tbh")
        #expect(fixture.recents.entries.first?.corrected == "мир")
        #expect(fixture.recents.entries.dropFirst().first?.original == "Pfrekxbk")
        #expect(fixture.recents.entries.dropFirst().first?.corrected == "Заключил")
    }

    @Test func russianWrongLayoutWordCanContainEnglishPeriodKeyAsLetter() async throws {
        let fixture = try Self.makeFixture(
            retypeSucceeds: true,
            initialLayoutID: "com.apple.keylayout.ABC",
            enabledLayouts: Self.multilingualRetypeSources()
        )
        fixture.appState.correctCommonTypos = true

        for event in try Self.wordEvents("pfrk.xbk", language: .en) {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil {
            fixture.recents.entries.first?.corrected == "заключил"
        }
        #expect(fixture.recents.entries.first?.original == "pfrk.xbk")
        #expect(fixture.recents.entries.first?.corrected == "заключил")

        for event in try Self.wordEvents("tbh", language: .en) {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil {
            fixture.recents.entries.first?.corrected == "мир"
        }
        #expect(fixture.recents.entries.first?.original == "tbh")
        #expect(fixture.recents.entries.first?.corrected == "мир")
        #expect(fixture.recents.entries.dropFirst().first?.original == "pfrk.xbk")
        #expect(fixture.recents.entries.dropFirst().first?.corrected == "заключил")
    }

    @Test func visibleLatinDictionaryWordSuppressesRenderedRussianDictionarySwitch() async throws {
        let fixture = try Self.makeFixture(
            retypeSucceeds: true,
            initialLayoutID: "com.apple.keylayout.RussianWin",
            enabledLayouts: Self.multilingualRetypeSources()
        )
        fixture.appState.correctCommonTypos = true

        for event in try Self.wordEvents("accent", language: .ro) {
            fixture.pipeline.handle(event)
        }

        await Self.waitForAsyncWorkWindow(nanoseconds: 50_000_000)
        #expect(fixture.recents.entries.isEmpty)
        #expect(fixture.output.selectedLayouts.isEmpty)
        #expect(fixture.output.playedFeedback.isEmpty)
    }

    @Test func snoozeCommitsWordsButSuppressesAutoSwitch() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: true)
        fixture.appState.startSnooze()
        let initialWords = fixture.stats.wordsCommittedTotal
        let initialSwitches = fixture.stats.autoSwitchesTotal

        for event in [
            Self.key(5, "g"),
            Self.key(4, "h"),
            Self.key(11, "b"),
            Self.key(2, "d"),
            Self.key(17, "t"),
            Self.key(45, "n"),
            Self.key(49, " ")
        ] {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil { fixture.stats.wordsCommittedTotal == initialWords + 1 }

        #expect(fixture.stats.wordsCommittedTotal == initialWords + 1)
        #expect(fixture.stats.autoSwitchesTotal == initialSwitches)
        #expect(fixture.recents.entries.isEmpty)
        #expect(fixture.output.postedKeys.isEmpty)
    }

    @Test func expiredSnoozeAllowsAutoSwitchAgain() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: true)
        fixture.appState.snoozedUntil = Date(timeIntervalSince1970: 1)
        let initialSwitches = fixture.stats.autoSwitchesTotal

        for event in [
            Self.key(5, "g"),
            Self.key(4, "h"),
            Self.key(11, "b"),
            Self.key(2, "d"),
            Self.key(17, "t"),
            Self.key(45, "n"),
            Self.key(49, " ")
        ] {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil { fixture.stats.autoSwitchesTotal == initialSwitches + 1 }

        #expect(fixture.stats.autoSwitchesTotal == initialSwitches + 1)
        #expect(fixture.appState.snoozedUntil == nil)
    }

    @Test func snoozeStartedBeforeDelayedEvaluationSuppressesPendingWord() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: true)
        let initialSwitches = fixture.stats.autoSwitchesTotal

        for event in [
            Self.key(5, "g"),
            Self.key(4, "h"),
            Self.key(11, "b"),
            Self.key(2, "d"),
            Self.key(17, "t"),
            Self.key(45, "n"),
            Self.key(49, " ")
        ] {
            fixture.pipeline.handle(event)
        }
        fixture.appState.startSnooze()
        await Self.waitForAsyncWorkWindow(nanoseconds: 250_000_000)

        #expect(fixture.stats.autoSwitchesTotal == initialSwitches)
        #expect(fixture.output.postedKeys.isEmpty)
    }

    @Test func digitPoisonsTokenUntilSeparator() throws {
        let currentDate = Date(timeIntervalSinceReferenceDate: 0)
        let buffer = WordBuffer(now: { currentDate })
        let detector = LayoutDetector(
            mapping: RuEnQwertyMapping(),
            dictionaries: [
                .en: CompositeDictionary(language: .en, parts: [
                    InMemoryDictionary(language: .en, words: ["book"]),
                    EmbeddedDictionaries.english()
                ]),
                .ru: EmbeddedDictionaries.russian(),
                .ro: EmbeddedDictionaries.romanian()
            ],
            ngrams: [
                .en: NGramModels.english(),
                .ru: NGramModels.russian(),
                .ro: NGramModels.romanian()
            ],
            thresholds: .default
        )
        let inputSources = InputSourceManager()
        let isolatedDefaults = try Self.makeDefaults()
        let pipeline = TypingPipeline(
            buffer: buffer,
            focused: Self.makeFocusedAppObserver(),
            detector: detector,
            retyper: Retyper(
                mapping: detector.mapping,
                enabledLayoutsProvider: { [] },
                currentLayoutIDProvider: { nil },
                refreshCurrentLayout: {},
                selectLayout: { _ in OSStatus(paramErr) },
                sleep: { _ in },
                postKeyEvent: { _, _ in },
                postUnicodeEvent: { _ in },
                capsLockGuard: Self.inertCapsLockGuard()
            ),
            inputSources: inputSources,
            exclusions: ExclusionList(defaults: isolatedDefaults, localizedNameProvider: { _ in nil }),
            stats: UsageStats(defaults: isolatedDefaults, now: { Date(timeIntervalSince1970: 0) }),
            recents: RecentSwitches(defaults: isolatedDefaults, makeEntryID: { Self.fixedID() }),
            tunables: .default,
            sleepBeforeSequenceFlush: { _ in },
            now: { currentDate }
        )
        let appState = AppState(defaults: isolatedDefaults, now: { currentDate })
        pipeline.appState = appState

        var committed: [CommittedWord] = []
        buffer.onCommitted = { committed.append($0) }

        for event in [
            Self.key(5, "g"),
            Self.key(4, "h"),
            Self.key(11, "b"),
            Self.key(18, "1"),
            Self.key(2, "d"),
            Self.key(17, "t"),
            Self.key(45, "n"),
            Self.key(49, " ")
        ] {
            pipeline.handle(event)
        }

        #expect(committed.isEmpty)
    }

    @Test func classifierRecognizesDigits() throws {
        #expect(KeyClassifier.classify(Self.key(18, "1")) == .digit)
    }

    @Test func twoWrongLayoutWordsAreRetypedAsSingleBlock() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: true)
        let initialSwitches = fixture.stats.autoSwitchesTotal

        for event in [
            Self.key(5, "g"), Self.key(4, "h"), Self.key(11, "b"), Self.key(2, "d"), Self.key(17, "t"), Self.key(45, "n"), Self.key(49, " "),
            Self.key(15, "r"), Self.key(3, "f"), Self.key(15, "r"), Self.key(49, " ")
        ] {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil(timeoutNanoseconds: 500_000_000) {
            fixture.stats.autoSwitchesTotal == initialSwitches + 1
        }

        #expect(fixture.stats.autoSwitchesTotal == initialSwitches + 1)
        #expect(fixture.recents.entries.count == 1)
        #expect(fixture.recents.entries.first?.original == "ghbdtn rfr")
        #expect(fixture.recents.entries.first?.corrected == "привет как")
        #expect(Array(fixture.output.postedKeys.prefix(11)) == Array(repeating: 51, count: 11))
        #expect(fixture.output.postedUnicode.isEmpty)
    }

    @Test func threeWrongLayoutWordsAreRetypedAsSingleBlock() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: true)
        let initialSwitches = fixture.stats.autoSwitchesTotal

        for event in [
            Self.key(5, "g"), Self.key(4, "h"), Self.key(11, "b"), Self.key(2, "d"), Self.key(17, "t"), Self.key(45, "n"), Self.key(49, " "),
            Self.key(15, "r"), Self.key(3, "f"), Self.key(15, "r"), Self.key(49, " "),
            Self.key(45, "n"), Self.key(3, "f"), Self.key(15, "r"), Self.key(49, " ")
        ] {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil(timeoutNanoseconds: 500_000_000) {
            fixture.stats.autoSwitchesTotal == initialSwitches + 1
        }

        #expect(fixture.stats.autoSwitchesTotal == initialSwitches + 1)
        #expect(fixture.recents.entries.count == 1)
        #expect(fixture.recents.entries.first?.original == "ghbdtn rfr nfr")
        #expect(fixture.recents.entries.first?.corrected == "привет как так")
    }

    @Test func multiWordBlockWithPunctuationRestoresFinalSeparatorAsUnicode() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: true)
        let initialSwitches = fixture.stats.autoSwitchesTotal

        for event in [
            Self.key(5, "g"), Self.key(4, "h"), Self.key(11, "b"), Self.key(2, "d"), Self.key(17, "t"), Self.key(45, "n"), Self.key(49, " "),
            Self.key(15, "r"), Self.key(3, "f"), Self.key(15, "r"), Self.key(18, "!")
        ] {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil(timeoutNanoseconds: 500_000_000) {
            fixture.stats.autoSwitchesTotal == initialSwitches + 1
        }

        #expect(fixture.stats.autoSwitchesTotal == initialSwitches + 1)
        #expect(fixture.recents.entries.count == 1)
        #expect(fixture.recents.entries.first?.original == "ghbdtn rfr")
        #expect(fixture.output.postedUnicode == ["!"])
    }

    @Test func focusChangeResetsPendingMultiWordSequence() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: true)
        let initialSwitches = fixture.stats.autoSwitchesTotal

        for event in [
            Self.key(5, "g"), Self.key(4, "h"), Self.key(11, "b"), Self.key(2, "d"), Self.key(17, "t"), Self.key(45, "n"), Self.key(49, " ")
        ] {
            fixture.pipeline.handle(event)
        }

        fixture.focused.onChange?()

        for event in [
            Self.key(15, "r"), Self.key(3, "f"), Self.key(15, "r"), Self.key(49, " ")
        ] {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil(timeoutNanoseconds: 500_000_000) {
            fixture.stats.autoSwitchesTotal == initialSwitches + 1
        }

        #expect(fixture.stats.autoSwitchesTotal == initialSwitches + 1)
        #expect(fixture.recents.entries.count == 1)
        #expect(fixture.recents.entries.first?.original == "rfr")
    }

    @Test func failedMultiWordRetypeDoesNotRecordStatsOrRecents() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: false)
        let initialSwitches = fixture.stats.autoSwitchesTotal

        for event in [
            Self.key(5, "g"), Self.key(4, "h"), Self.key(11, "b"), Self.key(2, "d"), Self.key(17, "t"), Self.key(45, "n"), Self.key(49, " "),
            Self.key(15, "r"), Self.key(3, "f"), Self.key(15, "r"), Self.key(49, " ")
        ] {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil(timeoutNanoseconds: 500_000_000) {
            !fixture.pipeline.isRetyping
        }

        #expect(fixture.stats.autoSwitchesTotal == initialSwitches)
        #expect(fixture.recents.entries.isEmpty)
        #expect(fixture.output.postedKeys.isEmpty)
        #expect(fixture.output.postedUnicode.isEmpty)
    }

    @Test func repeatedIdenticalMultiWordBlockIsSuppressedDuringCooldown() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: true)
        let initialSwitches = fixture.stats.autoSwitchesTotal
        let initialRecents = fixture.recents.entries.count

        let block = [
            Self.key(5, "g"), Self.key(4, "h"), Self.key(11, "b"), Self.key(2, "d"), Self.key(17, "t"), Self.key(45, "n"), Self.key(49, " "),
            Self.key(15, "r"), Self.key(3, "f"), Self.key(15, "r"), Self.key(49, " ")
        ]
        for event in block {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil(timeoutNanoseconds: 500_000_000) {
            fixture.stats.autoSwitchesTotal == initialSwitches + 1
        }
        let postedKeyCount = fixture.output.postedKeys.count

        for event in block {
            fixture.pipeline.handle(event)
        }
        await Self.waitForAsyncWorkWindow(nanoseconds: 100_000_000)

        #expect(fixture.stats.autoSwitchesTotal == initialSwitches + 1)
        #expect(fixture.recents.entries.count == initialRecents + 1)
        #expect(fixture.output.postedKeys.count == postedKeyCount)
    }

    @Test func multiWordCooldownDoesNotSuppressSameLastWordWithDifferentPreviousContext() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: true)
        let initialSwitches = fixture.stats.autoSwitchesTotal

        for event in [
            Self.key(5, "g"), Self.key(4, "h"), Self.key(11, "b"), Self.key(2, "d"), Self.key(17, "t"), Self.key(45, "n"), Self.key(49, " "),
            Self.key(15, "r"), Self.key(3, "f"), Self.key(15, "r"), Self.key(49, " ")
        ] {
            fixture.pipeline.handle(event)
        }
        await Self.waitUntil(timeoutNanoseconds: 500_000_000) {
            fixture.stats.autoSwitchesTotal == initialSwitches + 1
        }

        for event in [
            Self.key(45, "n"), Self.key(3, "f"), Self.key(15, "r"), Self.key(49, " "),
            Self.key(15, "r"), Self.key(3, "f"), Self.key(15, "r"), Self.key(49, " ")
        ] {
            fixture.pipeline.handle(event)
        }
        await Self.waitUntil(timeoutNanoseconds: 500_000_000) {
            fixture.stats.autoSwitchesTotal == initialSwitches + 2
        }

        #expect(fixture.stats.autoSwitchesTotal == initialSwitches + 2)
        #expect(fixture.recents.entries.first?.original == "nfr rfr")
        #expect(fixture.recents.entries.first?.corrected == "так как")
    }

    @Test func forceConvertLastSentenceConvertsTrailingSingleCharRun() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: true)
        fixture.appState.correctSingleCharacterWords = false

        // Type "z f " — 1-char tokens that auto-detect leaves as ambiguous
        // (below shortWordStrictMinLength). Sentence convert opts into single-char mode.
        for event in [
            Self.key(6, "z"),
            Self.key(49, " "),
            Self.key(3, "f"),
            Self.key(49, " ")
        ] {
            fixture.pipeline.handle(event)
        }

        let initialSwitches = fixture.stats.autoSwitchesTotal
        let initialRecents = fixture.recents.entries.count
        fixture.pipeline.forceConvertLastSentence()
        await Self.waitUntil { !fixture.pipeline.isRetyping }

        #expect(fixture.stats.autoSwitchesTotal == initialSwitches + 1)
        #expect(fixture.recents.entries.count == initialRecents + 1)
        #expect(fixture.recents.entries.first?.original == "z f")
        #expect(fixture.recents.entries.first?.corrected == "я а")
        #expect(fixture.output.selectedLayouts.contains("com.apple.keylayout.RussianWin"))
    }

    @Test func forceConvertLastSentenceStopsAtSentencePunctuation() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: true)
        fixture.appState.correctSingleCharacterWords = false

        // "z!" then "f " — '!' (keyCode 18 + Shift) is a sentence boundary
        // and is not ambiguous between EN/RU, so it commits the previous word.
        for event in [
            Self.key(6, "z"),
            KeyEvent(keyCode: 18, flags: .maskShift, unicode: "!"),
            Self.key(3, "f"),
            Self.key(49, " ")
        ] {
            fixture.pipeline.handle(event)
        }

        let initialSwitches = fixture.stats.autoSwitchesTotal
        fixture.pipeline.forceConvertLastSentence()
        await Self.waitUntil { !fixture.pipeline.isRetyping }

        #expect(fixture.stats.autoSwitchesTotal == initialSwitches + 1)
        #expect(fixture.recents.entries.first?.original == "f")
        #expect(fixture.recents.entries.first?.corrected == "а")
    }

    @Test func autoExtendIncludesRecentAmbiguousWordsWhenEnabled() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: true)
        fixture.appState.correctSingleCharacterWords = false
        fixture.appState.autoExtendRecentAmbiguous = true
        let initialSwitches = fixture.stats.autoSwitchesTotal

        // "z f " — both 1-char, auto-detector leaves them ambiguous (no retype).
        // Then "ghbdtn " — long wrong-layout word, triggers .switchAndRetype → "привет".
        // With auto-extend on, the burst should swallow "z" and "f" too → "я а привет".
        for event in [
            Self.key(6, "z"), Self.key(49, " "),
            Self.key(3, "f"), Self.key(49, " "),
            Self.key(5, "g"), Self.key(4, "h"), Self.key(11, "b"),
            Self.key(2, "d"), Self.key(17, "t"), Self.key(45, "n"),
            Self.key(49, " ")
        ] {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil(timeoutNanoseconds: 2_000_000_000) {
            fixture.stats.autoSwitchesTotal > initialSwitches && !fixture.pipeline.isRetyping
        }

        #expect(fixture.recents.entries.first?.original == "z f ghbdtn")
        #expect(fixture.recents.entries.first?.corrected == "я а привет")
        #expect(fixture.output.selectedLayouts.contains("com.apple.keylayout.RussianWin"))
    }

    @Test func autoExtendIncludesSingleCharBeforeWordWithInternalAmbiguousPunctuation() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: true)
        fixture.appState.correctSingleCharacterWords = false
        fixture.appState.autoExtendRecentAmbiguous = true
        let initialSwitches = fixture.stats.autoSwitchesTotal

        // Exact reproduction of the reported scenario: "z nt,z " typed on EN.
        // "z" (kc 6) commits as ambiguous on the first space.
        // "nt,z" (kc 45/17/43/6) — the ',' (kc 43) is an ambiguous-internal char that
        // TokenBoundaryPolicy keeps inside the word. The 4-char buffer renders as
        // Russian "тебя" and triggers .switchAndRetype.
        // With auto-extend on, the burst should pull "z" in too → "я тебя".
        for event in [
            Self.key(6, "z"), Self.key(49, " "),
            Self.key(45, "n"), Self.key(17, "t"), Self.key(43, ","), Self.key(6, "z"),
            Self.key(49, " ")
        ] {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil(timeoutNanoseconds: 2_000_000_000) {
            fixture.stats.autoSwitchesTotal > initialSwitches && !fixture.pipeline.isRetyping
        }

        #expect(fixture.recents.entries.first?.original == "z nt,z")
        #expect(fixture.recents.entries.first?.corrected == "я тебя")
    }

    @Test func autoExtendDisabledOnlyRetypesCurrentWord() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: true)
        fixture.appState.correctSingleCharacterWords = false
        fixture.appState.autoExtendRecentAmbiguous = false
        let initialSwitches = fixture.stats.autoSwitchesTotal

        for event in [
            Self.key(6, "z"), Self.key(49, " "),
            Self.key(3, "f"), Self.key(49, " "),
            Self.key(5, "g"), Self.key(4, "h"), Self.key(11, "b"),
            Self.key(2, "d"), Self.key(17, "t"), Self.key(45, "n"),
            Self.key(49, " ")
        ] {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil(timeoutNanoseconds: 2_000_000_000) {
            fixture.stats.autoSwitchesTotal > initialSwitches && !fixture.pipeline.isRetyping
        }

        #expect(fixture.recents.entries.first?.original == "ghbdtn")
        #expect(fixture.recents.entries.first?.corrected == "привет")
    }

    @Test func forceConvertLastSentenceDoesNothingWhenWordsAreCorrect() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: true)
        fixture.appState.correctSingleCharacterWords = false

        // "hello " stays as-is — detector returns .keep for the active English layout.
        for event in [
            Self.key(4, "h"),
            Self.key(14, "e"),
            Self.key(37, "l"),
            Self.key(37, "l"),
            Self.key(31, "o"),
            Self.key(49, " ")
        ] {
            fixture.pipeline.handle(event)
        }

        let initialSwitches = fixture.stats.autoSwitchesTotal
        let initialKeys = fixture.output.postedKeys.count
        fixture.pipeline.forceConvertLastSentence()
        await Self.waitForAsyncWorkWindow(nanoseconds: 50_000_000)

        #expect(fixture.stats.autoSwitchesTotal == initialSwitches)
        #expect(fixture.output.postedKeys.count == initialKeys)
    }

    private static func key(_ keyCode: CGKeyCode, _ unicode: String) -> KeyEvent {
        KeyEvent(keyCode: keyCode, unicode: unicode)
    }

    private static func wordEvents(_ text: String, language: LanguageID) throws -> [KeyEvent] {
        let mapping = RuEnQwertyMapping()
        var events: [KeyEvent] = []
        events.reserveCapacity(text.count + 1)
        for character in text {
            let encoded = try #require(mapping.keyCode(for: character, language: language))
            var flags: CGEventFlags = []
            if encoded.shift {
                flags.insert(.maskShift)
            }
            events.append(KeyEvent(
                keyCode: encoded.keyCode,
                flags: flags,
                unicode: String(character)
            ))
        }
        events.append(Self.key(49, " "))
        return events
    }

    private static func multilingualRetypeSources() -> [RetypeInputSource] {
        [
            RetypeInputSource(id: "com.apple.keylayout.ABC", primaryLanguage: "en"),
            RetypeInputSource(id: "com.apple.keylayout.RussianWin", primaryLanguage: "ru"),
            RetypeInputSource(id: "com.apple.keylayout.Romanian-Standard", primaryLanguage: "ro")
        ]
    }

    /// Pins the stateless cross-layout precedence end-to-end (EN-active layout).
    /// `expectedCorrected == nil` means the word must be kept (no retype).
    /// Keep this table in sync with docs/DecisionModel.md.
    @Test func crossLayoutPrecedenceTableProducesExpectedOutcomes() async throws {
        let cases: [(name: String, typed: String, expectedCorrected: String?)] = [
            ("wrong-layout EN→RU switches", "ghbdtn", "привет"),
            ("visible English dictionary word is kept", "book", nil),
            ("visible English dictionary word is kept (accent)", "accent", nil)
        ]
        for testCase in cases {
            let fixture = try Self.makeFixture(retypeSucceeds: true)
            for event in try Self.wordEvents(testCase.typed, language: .en) {
                fixture.pipeline.handle(event)
            }
            if let expected = testCase.expectedCorrected {
                await Self.waitUntil { fixture.recents.entries.first?.corrected == expected }
                #expect(fixture.recents.entries.first?.corrected == expected, "\(testCase.name)")
                #expect(fixture.recents.entries.first?.original == testCase.typed, "\(testCase.name)")
            } else {
                await Self.waitForAsyncWorkWindow(nanoseconds: 50_000_000)
                #expect(fixture.recents.entries.isEmpty, "\(testCase.name): expected no retype")
                #expect(fixture.output.selectedLayouts.isEmpty, "\(testCase.name): expected no layout switch")
            }
        }
    }

    @Test func rapidBurstOfWordsStaysConsistent() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: true)
        let initialCommitted = fixture.stats.wordsCommittedTotal
        let wordCount = 100

        for _ in 0..<wordCount {
            for event in try Self.wordEvents("ghbdtn", language: .en) {
                fixture.pipeline.handle(event)
            }
        }

        // Every committed word is counted synchronously; the burst must not drop,
        // double-count, or wedge the pipeline in a retyping state.
        await Self.waitUntil { !fixture.pipeline.isRetyping }
        #expect(fixture.stats.wordsCommittedTotal == initialCommitted + wordCount)
        #expect(!fixture.pipeline.isRetyping)
    }

    @Test func inlineAutoReplaceExpandsTriggerWord() async throws {
        let defaults = try #require(UserDefaults(suiteName: "TypingPipelineTests.autoReplace"))
        defaults.removePersistentDomain(forName: "TypingPipelineTests.autoReplace")
        let rules = AutoReplaceRules(defaults: defaults)
        rules.upsert(trigger: "brb", replacement: "be right back")

        let fixture = try Self.makeFixture(retypeSucceeds: true, autoReplaceRules: rules)
        for event in try Self.wordEvents("brb", language: .en) {
            fixture.pipeline.handle(event)
        }

        await Self.waitForAsyncWorkWindow(nanoseconds: 50_000_000)
        // 3 trigger chars + separator erased; replacement typed as Unicode; space re-emitted.
        #expect(Array(fixture.output.postedKeys.prefix(4)) == [51, 51, 51, 51])
        #expect(fixture.output.postedUnicode.contains("be right back"))
    }

    @Test func hotkeyAutoReplaceExpandsLiveBufferWord() async throws {
        let defaults = try #require(UserDefaults(suiteName: "TypingPipelineTests.autoReplaceHotkey"))
        defaults.removePersistentDomain(forName: "TypingPipelineTests.autoReplaceHotkey")
        let rules = AutoReplaceRules(defaults: defaults)
        rules.upsert(trigger: "omw", replacement: "on my way")

        let fixture = try Self.makeFixture(retypeSucceeds: true, autoReplaceRules: rules)
        // Type the trigger with no separator (live buffer), then fire the hotkey.
        for event in [Self.key(31, "o"), Self.key(46, "m"), Self.key(13, "w")] {
            fixture.pipeline.handle(event)
        }
        fixture.pipeline.expandCurrentWordViaHotkey()

        // 3 chars erased (no separator); replacement typed as Unicode.
        #expect(Array(fixture.output.postedKeys.prefix(3)) == [51, 51, 51])
        #expect(fixture.output.postedUnicode == ["on my way"])
    }

    @Test func mouseClickMidWordResetsBufferWithoutStaleFragment() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: true)

        // Type a fragment with no separator, then click (reset), then a full word.
        for event in [Self.key(5, "g"), Self.key(4, "h"), Self.key(11, "b")] {
            fixture.pipeline.handle(event)
        }
        fixture.pipeline.handle(KeyEvent(kind: .leftMouseDown, keyCode: 0, unicode: ""))
        for event in try Self.wordEvents("ghbdtn", language: .en) {
            fixture.pipeline.handle(event)
        }

        await Self.waitUntil { fixture.recents.entries.first?.corrected == "привет" }
        // The pre-click "ghb" must not leak into the correction's original text.
        #expect(fixture.recents.entries.first?.original == "ghbdtn")
        #expect(fixture.recents.entries.first?.corrected == "привет")
    }

    @Test func presentationModeSuppressesAutoSwitch() async throws {
        let fixture = try Self.makeFixture(retypeSucceeds: true, presentationDetector: PresentationModeDetector(
            frontmostBundleIDProvider: { "com.apple.iWork.Keynote" }
        ))
        let initialSwitches = fixture.stats.autoSwitchesTotal

        for event in [
            Self.key(5, "g"),
            Self.key(4, "h"),
            Self.key(11, "b"),
            Self.key(2, "d"),
            Self.key(17, "t"),
            Self.key(45, "n"),
            Self.key(49, " ")
        ] {
            fixture.pipeline.handle(event)
        }

        await Self.waitForAsyncWorkWindow(nanoseconds: 250_000_000)

        #expect(fixture.stats.autoSwitchesTotal == initialSwitches)
        #expect(fixture.output.postedKeys.isEmpty)
    }

    private static func makeFixture(
        retypeSucceeds: Bool,
        initialLayoutID: String = "com.apple.keylayout.ABC",
        enabledLayouts: [RetypeInputSource]? = nil,
        presentationDetector: PresentationModeDetector? = nil,
        detector injectedDetector: LayoutDetector? = nil,
        inputSources injectedInputSources: FakeInputSources? = nil,
        autoReplaceRules: AutoReplaceRules? = nil
    ) throws -> PipelineFixture {
        let enabledLayouts = enabledLayouts ?? [RetypeInputSource(id: "com.apple.keylayout.RussianWin", primaryLanguage: "ru")]
        let output = RetypeOutput()
        var currentLayoutID = initialLayoutID
        let currentDate = Date(timeIntervalSinceReferenceDate: 1_000)
        let buffer = WordBuffer(now: { currentDate })
        let detector = injectedDetector ?? LayoutDetector(
            mapping: RuEnQwertyMapping(),
            dictionaries: [
                .en: CompositeDictionary(language: .en, parts: [
                    InMemoryDictionary(language: .en, words: ["accent", "book"]),
                    EmbeddedDictionaries.english()
                ]),
                .ru: CompositeDictionary(language: .ru, parts: [
                    InMemoryDictionary(language: .ru, words: ["руда", "ищу", "заключил", "мир"]),
                    EmbeddedDictionaries.russian()
                ]),
                .ro: CompositeDictionary(language: .ro, parts: [
                    InMemoryDictionary(language: .ro, words: ["accent", "vbm"]),
                    EmbeddedDictionaries.romanian()
                ])
            ],
            ngrams: [
                .en: NGramModels.english(),
                .ru: NGramModels.russian(),
                .ro: NGramModels.romanian()
            ],
            romanianDiacriticResolver: RomanianDiacriticResolver(words: EmbeddedDictionaries.romanian().allWords),
            russianYoResolver: RussianYoResolver(words: ["ёжик", "все", "всё"]),
            spellingSuggestionProvider: FixedSuggestionProvider(suggestionsByWord: [
                "bokk": ["book"],
                "hellp": ["hello"],
                "ro:vbh": ["vbm"],
                "Заклучил": ["заключил"],
                "Закулчил": ["заключил"],
                "еир": ["мир"],
                "руддщ": ["руда"],
                "ищлл": ["ищу"]
            ]),
            thresholds: .default
        )
        let inputSources = injectedInputSources ?? FakeInputSources.defaultRuEn(currentID: initialLayoutID)
        let retyper = Retyper(
            mapping: detector.mapping,
            enabledLayoutsProvider: {
                enabledLayouts
            },
            currentLayoutIDProvider: { currentLayoutID },
            refreshCurrentLayout: {},
            selectLayout: { layout in
                output.selectedLayouts.append(layout.id)
                guard retypeSucceeds else { return OSStatus(paramErr) }
                currentLayoutID = layout.id
                return noErr
            },
            sleep: { _ in },
            postKeyEvent: { keyCode, _ in output.postedKeys.append(keyCode) },
            postUnicodeEvent: { output.postedUnicode.append($0) },
            capsLockGuard: Self.inertCapsLockGuard()
        )
        let isolatedDefaults = try Self.makeDefaults()
        let stats = UsageStats(defaults: isolatedDefaults, now: { Date(timeIntervalSince1970: 0) })
        let recents = RecentSwitches(defaults: isolatedDefaults, makeEntryID: { Self.fixedID() })
        let appState = AppState(defaults: isolatedDefaults, now: { currentDate })
        let focused = Self.makeFocusedAppObserver()
        let pipeline = TypingPipeline(
            buffer: buffer,
            focused: focused,
            detector: detector,
            retyper: retyper,
            inputSources: inputSources,
            soundFeedback: SoundFeedbackPlayer { output.playedFeedback.append($0) },
            visualFeedback: VisualFeedbackPlayer { output.visualFeedback.append($0) },
            presentationDetector: presentationDetector,
            exclusions: ExclusionList(defaults: isolatedDefaults, localizedNameProvider: { _ in nil }),
            stats: stats,
            recents: recents,
            autoReplaceRules: autoReplaceRules,
            tunables: .default,
            sleepBeforeSequenceFlush: { _ in await Task.yield() },
            now: { currentDate }
        )
        pipeline.appState = appState
        return PipelineFixture(
            pipeline: pipeline,
            appState: appState,
            stats: stats,
            recents: recents,
            output: output,
            focused: focused
        )
    }

    private static func waitUntil(
        timeoutNanoseconds: UInt64 = 200_000_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let step: UInt64 = 10_000_000
        var elapsed: UInt64 = 0
        while elapsed < timeoutNanoseconds {
            if condition() { return }
            await Task.yield()
            elapsed += step
        }
    }

    private static func inertCapsLockGuard() -> CapsLockGuard {
        CapsLockGuard(
            readCapsLockState: { false },
            setCapsLockState: { _ in true }
        )
    }

    private static func waitForAsyncWorkWindow(nanoseconds: UInt64) async {
        await waitUntil(timeoutNanoseconds: nanoseconds) { false }
    }
}

@MainActor
private final class RetypeOutput {
    var selectedLayouts: [String] = []
    var postedKeys: [CGKeyCode] = []
    var postedUnicode: [String] = []
    var playedFeedback: [CorrectionFeedbackKind] = []
    var visualFeedback: [CorrectionFeedbackKind] = []
}

@MainActor
private struct PipelineFixture {
    let pipeline: TypingPipeline
    let appState: AppState
    let stats: UsageStats
    let recents: RecentSwitches
    let output: RetypeOutput
    let focused: FocusedAppObserver
}

private struct FixedSuggestionProvider: SpellingSuggestionProviding {
    let suggestionsByWord: [String: [String]]

    func suggestions(for word: String, language: LanguageID) -> [String] {
        suggestionsByWord["\(language.rawValue):\(word)"] ?? suggestionsByWord[word] ?? []
    }
}

private struct FixedScoreScorer: LanguageScoring {
    let scores: [LanguageID: LanguageScore]

    func score(_ text: String, language: LanguageID) -> LanguageScore {
        scores[language] ?? LanguageScore(naturalLanguageProbability: nil, nGramScore: -.infinity)
    }
}
