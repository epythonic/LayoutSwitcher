import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import LayoutSwitcher

@MainActor
struct TypingPipelineTests {
    @Test func autoSwitchRecordsOnlyAfterSuccessfulRetype() async {
        let fixture = Self.makeFixture(retypeSucceeds: true)
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

    @Test func failedRetypeDoesNotRecordAutoSwitchOrRecent() async {
        let fixture = Self.makeFixture(retypeSucceeds: false)
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

    @Test func repeatedIdenticalSingleWordIsSuppressedDuringCooldown() async {
        let fixture = Self.makeFixture(retypeSucceeds: true)
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
        try? await Task.sleep(nanoseconds: 250_000_000)

        #expect(fixture.stats.autoSwitchesTotal == initialSwitches + 1)
        #expect(fixture.recents.entries.count == initialRecents + 1)
        #expect(fixture.output.postedKeys.count == postedKeyCount)
    }

    @Test func enterSeparatorCommitsButSuppressesAutoSwitch() async {
        let fixture = Self.makeFixture(retypeSucceeds: true)
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

    @Test func disabledPipelineDoesNotCommitOrRetype() async {
        let fixture = Self.makeFixture(retypeSucceeds: true)
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

        try? await Task.sleep(nanoseconds: 20_000_000)

        #expect(fixture.stats.wordsCommittedTotal == initialWords)
        #expect(fixture.stats.autoSwitchesTotal == initialSwitches)
        #expect(fixture.recents.entries.isEmpty)
        #expect(fixture.output.postedKeys.isEmpty)
    }

    @Test func snoozeCommitsWordsButSuppressesAutoSwitch() async {
        let fixture = Self.makeFixture(retypeSucceeds: true)
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

    @Test func expiredSnoozeAllowsAutoSwitchAgain() async {
        let fixture = Self.makeFixture(retypeSucceeds: true)
        fixture.appState.snoozedUntil = Date().addingTimeInterval(-1)
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

    @Test func snoozeStartedBeforeDelayedEvaluationSuppressesPendingWord() async {
        let fixture = Self.makeFixture(retypeSucceeds: true)
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
        try? await Task.sleep(nanoseconds: 250_000_000)

        #expect(fixture.stats.autoSwitchesTotal == initialSwitches)
        #expect(fixture.output.postedKeys.isEmpty)
    }

    @Test func digitPoisonsTokenUntilSeparator() {
        let buffer = WordBuffer()
        let detector = LayoutDetector(
            mapping: RuEnQwertyMapping(),
            dictionaries: [
                .en: EmbeddedDictionaries.english(),
                .ru: EmbeddedDictionaries.russian(),
                .ro: EmbeddedDictionaries.romanian()
            ],
            ngrams: [
                .en: NGramModels.english(),
                .ru: NGramModels.russian(),
                .ro: NGramModels.romanian()
            ]
        )
        let inputSources = InputSourceManager()
        let isolatedDefaults = UserDefaults(suiteName: "TypingPipelineTests-\(UUID().uuidString)") ?? .standard
        let pipeline = TypingPipeline(
            buffer: buffer,
            focused: FocusedAppObserver(),
            detector: detector,
            retyper: Retyper(mapping: detector.mapping, inputSources: inputSources),
            inputSources: inputSources,
            exclusions: ExclusionList(defaults: isolatedDefaults),
            stats: UsageStats(defaults: isolatedDefaults),
            recents: RecentSwitches(defaults: isolatedDefaults)
        )
        let appState = AppState(defaults: isolatedDefaults)
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

    @Test func classifierRecognizesDigits() {
        #expect(KeyClassifier.classify(Self.key(18, "1")) == .digit)
    }

    @Test func twoWrongLayoutWordsAreRetypedAsSingleBlock() async {
        let fixture = Self.makeFixture(retypeSucceeds: true)
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

    @Test func threeWrongLayoutWordsAreRetypedAsSingleBlock() async {
        let fixture = Self.makeFixture(retypeSucceeds: true)
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

    @Test func multiWordBlockWithPunctuationRestoresFinalSeparatorAsUnicode() async {
        let fixture = Self.makeFixture(retypeSucceeds: true)
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

    @Test func focusChangeResetsPendingMultiWordSequence() async {
        let fixture = Self.makeFixture(retypeSucceeds: true)
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

    @Test func failedMultiWordRetypeDoesNotRecordStatsOrRecents() async {
        let fixture = Self.makeFixture(retypeSucceeds: false)
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

    @Test func repeatedIdenticalMultiWordBlockIsSuppressedDuringCooldown() async {
        let fixture = Self.makeFixture(retypeSucceeds: true)
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
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(fixture.stats.autoSwitchesTotal == initialSwitches + 1)
        #expect(fixture.recents.entries.count == initialRecents + 1)
        #expect(fixture.output.postedKeys.count == postedKeyCount)
    }

    @Test func multiWordCooldownDoesNotSuppressSameLastWordWithDifferentPreviousContext() async {
        let fixture = Self.makeFixture(retypeSucceeds: true)
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

    @Test func forceConvertLastSentenceConvertsTrailingSingleCharRun() async {
        let fixture = Self.makeFixture(retypeSucceeds: true)
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

    @Test func forceConvertLastSentenceStopsAtSentencePunctuation() async {
        let fixture = Self.makeFixture(retypeSucceeds: true)
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

    @Test func autoExtendIncludesRecentAmbiguousWordsWhenEnabled() async {
        let fixture = Self.makeFixture(retypeSucceeds: true)
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

    @Test func autoExtendDisabledOnlyRetypesCurrentWord() async {
        let fixture = Self.makeFixture(retypeSucceeds: true)
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

    @Test func forceConvertLastSentenceDoesNothingWhenWordsAreCorrect() async {
        let fixture = Self.makeFixture(retypeSucceeds: true)
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
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(fixture.stats.autoSwitchesTotal == initialSwitches)
        #expect(fixture.output.postedKeys.count == initialKeys)
    }

    private static func key(_ keyCode: CGKeyCode, _ unicode: String) -> KeyEvent {
        KeyEvent(keyCode: keyCode, unicode: unicode)
    }

    @Test func presentationModeSuppressesAutoSwitch() async {
        let fixture = Self.makeFixture(retypeSucceeds: true, presentationDetector: PresentationModeDetector(
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

        try? await Task.sleep(nanoseconds: 250_000_000)

        #expect(fixture.stats.autoSwitchesTotal == initialSwitches)
        #expect(fixture.output.postedKeys.isEmpty)
    }

    private static func makeFixture(
        retypeSucceeds: Bool,
        initialLayoutID: String = "com.apple.keylayout.ABC",
        enabledLayouts: [RetypeInputSource]? = nil,
        presentationDetector: PresentationModeDetector? = nil
    ) -> PipelineFixture {
        let enabledLayouts = enabledLayouts ?? [RetypeInputSource(id: "com.apple.keylayout.RussianWin", primaryLanguage: "ru")]
        let output = RetypeOutput()
        var currentLayoutID = initialLayoutID
        let buffer = WordBuffer()
        let detector = LayoutDetector(
            mapping: RuEnQwertyMapping(),
            dictionaries: [
                .en: EmbeddedDictionaries.english(),
                .ru: EmbeddedDictionaries.russian(),
                .ro: EmbeddedDictionaries.romanian()
            ],
            ngrams: [
                .en: NGramModels.english(),
                .ru: NGramModels.russian(),
                .ro: NGramModels.romanian()
            ],
            romanianDiacriticResolver: RomanianDiacriticResolver(words: EmbeddedDictionaries.romanian().allWords)
        )
        let inputSources = FakeInputSources.defaultRuEn(currentID: initialLayoutID)
        let retyper = Retyper(
            mapping: detector.mapping,
            inputSources: inputSources,
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
            postUnicodeEvent: { output.postedUnicode.append($0) }
        )
        let isolatedDefaults = UserDefaults(suiteName: "LayoutSwitcherTests-\(UUID().uuidString)")
            ?? UserDefaults.standard
        let stats = UsageStats(defaults: isolatedDefaults)
        let recents = RecentSwitches(defaults: isolatedDefaults)
        let appState = AppState(defaults: isolatedDefaults)
        let focused = FocusedAppObserver()
        let pipeline = TypingPipeline(
            buffer: buffer,
            focused: focused,
            detector: detector,
            retyper: retyper,
            inputSources: inputSources,
            presentationDetector: presentationDetector,
            exclusions: ExclusionList(defaults: isolatedDefaults),
            stats: stats,
            recents: recents
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
            try? await Task.sleep(nanoseconds: step)
            elapsed += step
        }
    }
}

@MainActor
private final class RetypeOutput {
    var selectedLayouts: [String] = []
    var postedKeys: [CGKeyCode] = []
    var postedUnicode: [String] = []
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
