import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct SwiftSafetyRulesTests {
    private typealias FileEnumerator = (
        _ root: URL,
        _ keys: [URLResourceKey]?,
        _ options: FileManager.DirectoryEnumerationOptions
    ) -> FileManager.DirectoryEnumerator?

    @Test func swiftSourcesDoNotUseForceOperations() throws {
        let projectRoot = try #require(Self.projectRoot())
        let sourceRoots = [
            projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true),
            projectRoot.appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
        ]
        let files = try sourceRoots.flatMap(Self.swiftFiles)
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.forceOperationViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden Swift force operations:\n\(violations.joined(separator: "\n"))")
    }

    @Test func swiftSourcesDoNotUseRuntimeTrapAPIs() throws {
        let projectRoot = try #require(Self.projectRoot())
        let sourceRoots = [
            projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true),
            projectRoot.appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
        ]
        let files = try sourceRoots.flatMap(Self.swiftFiles)
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.runtimeTrapViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden runtime trap APIs:\n\(violations.joined(separator: "\n"))")
    }

    @Test func testsDoNotUseUncontrolledSleepAPIs() throws {
        let projectRoot = try #require(Self.projectRoot())
        let testRoot = projectRoot.appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
        let files = try Self.swiftFiles(in: testRoot)
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.uncontrolledSleepViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden uncontrolled sleep APIs in tests:\n\(violations.joined(separator: "\n"))")
    }

    @Test func unitTestsDoNotUseWallClockAPIs() throws {
        let projectRoot = try #require(Self.projectRoot())
        let testRoot = projectRoot.appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
        let files = try Self.swiftFiles(in: testRoot)
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.wallClockViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden wall-clock APIs in unit tests:\n\(violations.joined(separator: "\n"))")
    }

    @Test func unitTestsDoNotUseRandomAPIs() throws {
        let projectRoot = try #require(Self.projectRoot())
        let testRoot = projectRoot.appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
        let files = try Self.swiftFiles(in: testRoot)
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.randomAPIViolations(in: sanitizedSource, path: relativePath))
            violations.append(contentsOf: Self.randomUserDefaultsSuiteNameViolations(in: source, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden random APIs in unit tests:\n\(violations.joined(separator: "\n"))")
    }

    @Test func swiftSourcesDoNotUseUncheckedSendable() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let testRoot = projectRoot.appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
        let files = try [appRoot, testRoot].flatMap { try Self.swiftFiles(in: $0) }
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.uncheckedSendableViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden unchecked Sendable usage:\n\(violations.joined(separator: "\n"))")
    }

    @Test func swiftSourcesDoNotUseUnauditedUnsafeIsolationBypasses() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let testRoot = projectRoot.appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
        let files = try [appRoot, testRoot].flatMap { try Self.swiftFiles(in: $0) }
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.unsafeIsolationBypassViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden unaudited actor isolation bypasses:\n\(violations.joined(separator: "\n"))")
    }

    @Test func swiftSourcesDoNotDefineSingletonSharedState() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let testRoot = projectRoot.appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
        let files = try [appRoot, testRoot].flatMap { try Self.swiftFiles(in: $0) }
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.singletonSharedStateViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden singleton shared state definitions:\n\(violations.joined(separator: "\n"))")
    }

    @Test func swiftSourcesDoNotDefineStoredStaticMutableState() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let testRoot = projectRoot.appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
        let files = try [appRoot, testRoot].flatMap { try Self.swiftFiles(in: $0) }
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.staticMutableStateViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden stored static mutable state:\n\(violations.joined(separator: "\n"))")
    }

    @Test func swiftSourcesDoNotDefineStaticDateFormatters() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let testRoot = projectRoot.appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
        let files = try [appRoot, testRoot].flatMap { try Self.swiftFiles(in: $0) }
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.staticDateFormatterViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden static DateFormatter instances:\n\(violations.joined(separator: "\n"))")
    }

    @Test func swiftSourcesDoNotDefineStaticLiveInstances() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let testRoot = projectRoot.appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
        let files = try [appRoot, testRoot].flatMap { try Self.swiftFiles(in: $0) }
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.staticLiveInstanceViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden static live service instances:\n\(violations.joined(separator: "\n"))")
    }

    @Test func capsLockGuardRequiresExplicitSideEffectClosures() throws {
        let projectRoot = try #require(Self.projectRoot())
        let relativePath = "LayoutSwitcher/Mapping/CapsLockGuard.swift"
        let file = projectRoot.appendingPathComponent(relativePath)
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

        #expect(!sanitizedSource.contains("= CapsLockGuard.liveReadCapsLockState"))
        #expect(!sanitizedSource.contains("= CapsLockGuard.liveSetCapsLockState"))
        #expect(sanitizedSource.contains("static func live() -> CapsLockGuard"))
    }

    @Test func wordBufferRequiresExplicitClock() throws {
        let projectRoot = try #require(Self.projectRoot())
        let relativePath = "LayoutSwitcher/Buffer/WordBuffer.swift"
        let file = projectRoot.appendingPathComponent(relativePath)
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

        #expect(!sanitizedSource.contains("= Date.init"))
        #expect(!sanitizedSource.contains("= Date()"))
        #expect(sanitizedSource.contains("init(now: @escaping @MainActor () -> Date)"))
    }

    @Test func hotkeyCoordinatorRequiresExplicitClock() throws {
        let projectRoot = try #require(Self.projectRoot())
        let relativePath = "LayoutSwitcher/Hotkeys/HotkeyCoordinator.swift"
        let file = projectRoot.appendingPathComponent(relativePath)
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

        #expect(!sanitizedSource.contains("= Date.init"))
        #expect(!sanitizedSource.contains("= Date()"))
        #expect(sanitizedSource.contains("now: @escaping @MainActor () -> Date"))
    }

    @Test func recentSwitchesRequiresExplicitEntryIDFactory() throws {
        let projectRoot = try #require(Self.projectRoot())
        let relativePath = "LayoutSwitcher/Stats/RecentSwitches.swift"
        let file = projectRoot.appendingPathComponent(relativePath)
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

        #expect(!sanitizedSource.contains("id: UUID = UUID()"))
        #expect(!sanitizedSource.contains("UUID()"))
        #expect(sanitizedSource.contains("makeEntryID: @escaping @MainActor () -> UUID"))
    }

    @Test func onboardingCompletionStoreRequiresExplicitDefaults() throws {
        let projectRoot = try #require(Self.projectRoot())
        let relativePath = "LayoutSwitcher/App/OnboardingCompletionStore.swift"
        let file = projectRoot.appendingPathComponent(relativePath)
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

        #expect(!sanitizedSource.contains("UserDefaults = .standard"))
        #expect(!sanitizedSource.contains("UserDefaults.standard"))
        #expect(sanitizedSource.contains("defaults: UserDefaults"))
    }

    @Test func hotkeyRegistryRequiresExplicitDefaults() throws {
        let projectRoot = try #require(Self.projectRoot())
        let relativePath = "LayoutSwitcher/Hotkeys/HotkeyRegistry.swift"
        let file = projectRoot.appendingPathComponent(relativePath)
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

        #expect(!sanitizedSource.contains("UserDefaults = .standard"))
        #expect(!sanitizedSource.contains("UserDefaults.standard"))
        #expect(sanitizedSource.contains("init(defaults: UserDefaults)"))
    }

    @Test func recentSwitchesRequiresExplicitDefaults() throws {
        let projectRoot = try #require(Self.projectRoot())
        let relativePath = "LayoutSwitcher/Stats/RecentSwitches.swift"
        let file = projectRoot.appendingPathComponent(relativePath)
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

        #expect(!sanitizedSource.contains("UserDefaults = .standard"))
        #expect(!sanitizedSource.contains("UserDefaults.standard"))
        #expect(sanitizedSource.contains("defaults: UserDefaults"))
        #expect(sanitizedSource.contains("makeEntryID: @escaping @MainActor () -> UUID"))
    }

    @Test func perAppLayoutPreferencesRequiresExplicitDefaults() throws {
        let projectRoot = try #require(Self.projectRoot())
        let relativePath = "LayoutSwitcher/Stats/PerAppLayoutPreferences.swift"
        let file = projectRoot.appendingPathComponent(relativePath)
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

        #expect(!sanitizedSource.contains("UserDefaults = .standard"))
        #expect(!sanitizedSource.contains("UserDefaults.standard"))
        #expect(sanitizedSource.contains("defaults: UserDefaults"))
        #expect(sanitizedSource.contains("appNameProvider: @escaping @MainActor (String) -> String?"))
    }

    @Test func usageStatsRequiresExplicitDefaultsAndClock() throws {
        let projectRoot = try #require(Self.projectRoot())
        let relativePath = "LayoutSwitcher/Stats/UsageStats.swift"
        let file = projectRoot.appendingPathComponent(relativePath)
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

        #expect(!sanitizedSource.contains("UserDefaults = .standard"))
        #expect(!sanitizedSource.contains("UserDefaults.standard"))
        #expect(!sanitizedSource.contains("Date = Date.init"))
        #expect(sanitizedSource.contains("init(defaults: UserDefaults, now: @escaping @MainActor () -> Date)"))
    }

    @Test func appStateRequiresExplicitDefaultsAndClock() throws {
        let projectRoot = try #require(Self.projectRoot())
        let relativePath = "LayoutSwitcher/App/AppState.swift"
        let file = projectRoot.appendingPathComponent(relativePath)
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

        #expect(!sanitizedSource.contains("UserDefaults = .standard"))
        #expect(!sanitizedSource.contains("UserDefaults.standard"))
        #expect(!sanitizedSource.contains("Date = Date.init"))
        #expect(sanitizedSource.contains("init(defaults: UserDefaults, now: @escaping @MainActor () -> Date)"))
    }

    @Test func exclusionListRequiresExplicitDefaultsAndWorkspace() throws {
        let projectRoot = try #require(Self.projectRoot())
        let relativePath = "LayoutSwitcher/Stats/ExclusionList.swift"
        let file = projectRoot.appendingPathComponent(relativePath)
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

        #expect(!sanitizedSource.contains("UserDefaults = .standard"))
        #expect(!sanitizedSource.contains("UserDefaults.standard"))
        #expect(!sanitizedSource.contains("NSWorkspace = .shared"))
        #expect(sanitizedSource.contains("convenience init(\n        defaults: UserDefaults,\n        workspace: NSWorkspace\n    )"))
        #expect(sanitizedSource.contains("init(\n        defaults: UserDefaults,\n        localizedNameProvider: @escaping @MainActor (String) -> String?\n    )"))
    }

    @Test func learningCacheRequiresExplicitDefaultsClockAndIDFactory() throws {
        let projectRoot = try #require(Self.projectRoot())
        let relativePath = "LayoutSwitcher/Pipeline/LearningCache.swift"
        let file = projectRoot.appendingPathComponent(relativePath)
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

        #expect(!sanitizedSource.contains("UserDefaults = .standard"))
        #expect(!sanitizedSource.contains("UserDefaults.standard"))
        #expect(!sanitizedSource.contains("Date = Date.init"))
        #expect(!sanitizedSource.contains("UUID = UUID.init"))
        #expect(sanitizedSource.contains("init(\n        defaults: UserDefaults,\n        now: @escaping @MainActor () -> Date,\n        makeEntryID: @escaping @MainActor () -> UUID\n    )"))
    }

    @Test func systemSpellCheckerStaysInjectedOutsideAppBoundary() throws {
        let projectRoot = try #require(Self.projectRoot())
        let dictionaryFile = projectRoot.appendingPathComponent("LayoutSwitcher/Detector/SystemSpellChecker.swift")
        let defaultsFile = projectRoot.appendingPathComponent("LayoutSwitcher/Detector/LayoutDetector+Defaults.swift")
        let dictionarySource = Self.removingCommentsAndStringLiterals(
            from: try String(contentsOf: dictionaryFile, encoding: .utf8)
        )
        let defaultsSource = Self.removingCommentsAndStringLiterals(
            from: try String(contentsOf: defaultsFile, encoding: .utf8)
        )

        #expect(!dictionarySource.contains("NSSpellChecker.shared"))
        #expect(!dictionarySource.contains("checker: any SpellChecking ="))
        #expect(!defaultsSource.contains("NSSpellChecker.shared"))
        #expect(defaultsSource.contains("systemSpellChecker: any SpellChecking"))
        #expect(defaultsSource.contains("SystemSpellCheckerDictionary(language: lang, checker: systemSpellChecker)"))
    }

    @Test func naturalLanguageScorerPolicyStaysExplicit() throws {
        let projectRoot = try #require(Self.projectRoot())
        let scorerFile = projectRoot.appendingPathComponent("LayoutSwitcher/Detector/NaturalLanguageScorer.swift")
        let hybridFile = projectRoot.appendingPathComponent("LayoutSwitcher/Detector/HybridLanguageScorer.swift")
        let defaultsFile = projectRoot.appendingPathComponent("LayoutSwitcher/Detector/LayoutDetector+Defaults.swift")
        let scorerSource = Self.removingCommentsAndStringLiterals(
            from: try String(contentsOf: scorerFile, encoding: .utf8)
        )
        let hybridSource = Self.removingCommentsAndStringLiterals(
            from: try String(contentsOf: hybridFile, encoding: .utf8)
        )
        let defaultsSource = Self.removingCommentsAndStringLiterals(
            from: try String(contentsOf: defaultsFile, encoding: .utf8)
        )

        #expect(!scorerSource.contains("DetectionThresholds.default"))
        #expect(!scorerSource.contains("minimumTextLength: Int ="))
        #expect(!scorerSource.contains("maximumHypotheses: Int ="))
        #expect(!hybridSource.contains("NaturalLanguageScorer()"))
        #expect(!hybridSource.contains("NaturalLanguageScorer? ="))
        #expect(defaultsSource.contains("minimumTextLength: thresholds.naturalLanguageMinWordLength"))
        #expect(defaultsSource.contains("maximumHypotheses: LanguageID.allCases.count"))
    }

    @Test func bundleNameLookupsStayInjectedOutsideAppBoundary() throws {
        let projectRoot = try #require(Self.projectRoot())
        let relativePaths = [
            "LayoutSwitcher/Hotkeys/HotkeyCoordinator.swift",
            "LayoutSwitcher/Pipeline/RetypeDispatcher.swift",
            "LayoutSwitcher/Stats/PerAppLayoutPreferences.swift"
        ]

        for relativePath in relativePaths {
            let file = projectRoot.appendingPathComponent(relativePath)
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

            #expect(!sanitizedSource.contains("ExclusionList.localizedName"))
        }
    }

    @Test func smartPasteKeepsProductionDependenciesOnAppBoundary() throws {
        let projectRoot = try #require(Self.projectRoot())
        let relativePath = "LayoutSwitcher/Mapping/SmartPaste.swift"
        let file = projectRoot.appendingPathComponent(relativePath)
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
        let sleepViolations = Self.uncontrolledSleepViolations(in: sanitizedSource, path: relativePath)

        #expect(sleepViolations.isEmpty, "SmartPaste must receive delays through injected closure:\n\(sleepViolations.joined(separator: "\n"))")
        #expect(!sanitizedSource.contains("NSPasteboard.general"))
        #expect(sanitizedSource.contains("pasteboardRead: @escaping @MainActor () -> String?"))
    }

    @Test func smartPasteTestsUseExpectInsteadOfIssueRecord() throws {
        let projectRoot = try #require(Self.projectRoot())
        let relativePath = "LayoutSwitcherTests/SmartPasteTests.swift"
        let file = projectRoot.appendingPathComponent(relativePath)
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

        #expect(!sanitizedSource.contains("Issue.record"))
    }

    @Test func selectionConverterTestsUseExpectInsteadOfIssueRecord() throws {
        let projectRoot = try #require(Self.projectRoot())
        let relativePath = "LayoutSwitcherTests/SelectionConverterTests.swift"
        let file = projectRoot.appendingPathComponent(relativePath)
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

        #expect(!sanitizedSource.contains("Issue.record"))
    }

    @Test func helpContentTestsUseRequireInsteadOfIssueRecord() throws {
        let projectRoot = try #require(Self.projectRoot())
        let relativePath = "LayoutSwitcherTests/HelpContentTests.swift"
        let file = projectRoot.appendingPathComponent(relativePath)
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

        #expect(!sanitizedSource.contains("Issue.record"))
    }

    @Test func languageScorerTestsUseRequireInsteadOfIssueRecord() throws {
        let projectRoot = try #require(Self.projectRoot())
        let relativePath = "LayoutSwitcherTests/LanguageScorerTests.swift"
        let file = projectRoot.appendingPathComponent(relativePath)
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

        #expect(!sanitizedSource.contains("Issue.record"))
    }

    @Test func localizationCatalogTestsUseRequireInsteadOfIssueRecord() throws {
        let projectRoot = try #require(Self.projectRoot())
        let relativePath = "LayoutSwitcherTests/LocalizationCatalogTests.swift"
        let file = projectRoot.appendingPathComponent(relativePath)
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

        #expect(!sanitizedSource.contains("Issue.record"))
    }

    @Test func selectionConverterKeepsProductionDependenciesInjected() throws {
        let projectRoot = try #require(Self.projectRoot())
        let relativePath = "LayoutSwitcher/Mapping/SelectionConverter.swift"
        let file = projectRoot.appendingPathComponent(relativePath)
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
        let sleepViolations = Self.uncontrolledSleepViolations(in: sanitizedSource, path: relativePath)

        #expect(sleepViolations.isEmpty, "SelectionConverter must receive delays through injected closure:\n\(sleepViolations.joined(separator: "\n"))")
        #expect(!sanitizedSource.contains("NSPasteboard.general"))
        #expect(!sanitizedSource.contains("AXUIElementCreateSystemWide"))
        #expect(sanitizedSource.contains("focusedElementProvider: @escaping @MainActor () -> AXUIElement?"))
    }

    @Test func swiftSourcesKeepInMemoryDictionaryValueTyped() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let testRoot = projectRoot.appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
        let files = try [appRoot, testRoot].flatMap { try Self.swiftFiles(in: $0) }
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.inMemoryDictionaryReferenceTypeViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden reference-typed InMemoryDictionary declarations:\n\(violations.joined(separator: "\n"))")
    }

    @Test func swiftSourcesKeepPresentationModeDetectorValueTyped() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let testRoot = projectRoot.appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
        let files = try [appRoot, testRoot].flatMap { try Self.swiftFiles(in: $0) }
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.presentationModeDetectorReferenceTypeViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden reference-typed PresentationModeDetector declarations:\n\(violations.joined(separator: "\n"))")
    }

    @Test func swiftSourcesKeepLearningCacheValueTyped() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let testRoot = projectRoot.appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
        let files = try [appRoot, testRoot].flatMap { try Self.swiftFiles(in: $0) }
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.learningCacheReferenceTypeViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden reference-typed LearningCache declarations:\n\(violations.joined(separator: "\n"))")
    }

    @Test func swiftSourcesKeepLayoutDetectorValueTyped() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let testRoot = projectRoot.appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
        let files = try [appRoot, testRoot].flatMap { try Self.swiftFiles(in: $0) }
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.layoutDetectorReferenceTypeViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden reference-typed LayoutDetector declarations:\n\(violations.joined(separator: "\n"))")
    }

    @Test func layoutDetectorThresholdsStayExplicitAtConstructionBoundaries() throws {
        let projectRoot = try #require(Self.projectRoot())
        let detectorFile = projectRoot.appendingPathComponent("LayoutSwitcher/Detector/LayoutDetector.swift")
        let defaultsFile = projectRoot.appendingPathComponent("LayoutSwitcher/Detector/LayoutDetector+Defaults.swift")
        let detectorSource = Self.removingCommentsAndStringLiterals(
            from: try String(contentsOf: detectorFile, encoding: .utf8)
        )
        let defaultsSource = Self.removingCommentsAndStringLiterals(
            from: try String(contentsOf: defaultsFile, encoding: .utf8)
        )

        #expect(!detectorSource.contains("DetectionThresholds = .default"))
        #expect(!defaultsSource.contains("DetectionThresholds = .default"))
        #expect(detectorSource.contains("thresholds: DetectionThresholds\n    )"))
        #expect(defaultsSource.contains("thresholds: DetectionThresholds\n    ) -> LayoutDetector"))
        #expect(defaultsSource.contains("thresholds: thresholds"))
    }

    @Test func swiftSourcesKeepCompositeDictionaryValueTyped() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let testRoot = projectRoot.appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
        let files = try [appRoot, testRoot].flatMap { try Self.swiftFiles(in: $0) }
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.compositeDictionaryReferenceTypeViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden reference-typed CompositeDictionary declarations:\n\(violations.joined(separator: "\n"))")
    }

    @Test func swiftSourcesKeepLaunchAtLoginManagerValueTyped() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let testRoot = projectRoot.appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
        let files = try [appRoot, testRoot].flatMap { try Self.swiftFiles(in: $0) }
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.launchAtLoginManagerReferenceTypeViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden reference-typed LaunchAtLoginManager declarations:\n\(violations.joined(separator: "\n"))")
    }

    @Test func swiftSourcesKeepSmartPasteValueTyped() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let testRoot = projectRoot.appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
        let files = try [appRoot, testRoot].flatMap { try Self.swiftFiles(in: $0) }
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.smartPasteReferenceTypeViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden reference-typed SmartPaste declarations:\n\(violations.joined(separator: "\n"))")
    }

    @Test func swiftSourcesKeepSelectionConverterValueTyped() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let testRoot = projectRoot.appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
        let files = try [appRoot, testRoot].flatMap { try Self.swiftFiles(in: $0) }
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.selectionConverterReferenceTypeViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden reference-typed SelectionConverter declarations:\n\(violations.joined(separator: "\n"))")
    }

    @Test func swiftSourcesKeepRetyperValueTyped() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let testRoot = projectRoot.appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
        let files = try [appRoot, testRoot].flatMap { try Self.swiftFiles(in: $0) }
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.retyperReferenceTypeViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden reference-typed Retyper declarations:\n\(violations.joined(separator: "\n"))")
    }

    @Test func appSourcesKeepReferenceTypesFinal() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let files = try Self.swiftFiles(in: appRoot)
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.nonFinalClassViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Non-final reference type declarations:\n\(violations.joined(separator: "\n"))")
    }

    @Test func unitTestsDoNotUseXCTestAPIs() throws {
        let projectRoot = try #require(Self.projectRoot())
        let testRoot = projectRoot.appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
        let files = try Self.swiftFiles(in: testRoot)
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.xctestViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden XCTest APIs in unit tests:\n\(violations.joined(separator: "\n"))")
    }

    @Test func appSourcesUseLoggerInsteadOfConsoleLogging() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let files = try Self.swiftFiles(in: appRoot)
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.consoleLoggingViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden console logging in app sources:\n\(violations.joined(separator: "\n"))")
    }

    @Test func appSourcesAvoidLegacyDispatchQueueScheduling() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let files = try Self.swiftFiles(in: appRoot)
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.legacyDispatchQueueViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden legacy DispatchQueue scheduling in app sources:\n\(violations.joined(separator: "\n"))")
    }

    @Test func appSourcesUseExplicitActorOnUnstructuredTasks() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let files = try Self.swiftFiles(in: appRoot)
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.explicitActorTaskViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Unstructured Task closures without explicit actor:\n\(violations.joined(separator: "\n"))")
    }

    @Test func appSourcesDeclareLoggerInterpolationPrivacy() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let files = try Self.swiftFiles(in: appRoot)
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.loggerInterpolationPrivacyViolations(in: source, path: relativePath))
        }

        #expect(violations.isEmpty, "Logger interpolations must declare privacy:\n\(violations.joined(separator: "\n"))")
    }

    @Test func appSourcesUseConsistentLoggerSubsystemAndCategories() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let files = try Self.swiftFiles(in: appRoot)
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.loggerDeclarationViolations(in: source, path: relativePath))
        }

        #expect(violations.isEmpty, "Logger declarations must use the project subsystem and PascalCase categories:\n\(violations.joined(separator: "\n"))")
    }

    @Test func appSourcesDoNotLeaveTodoMarkers() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let files = try Self.swiftFiles(in: appRoot)
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.todoMarkerViolations(in: source, path: relativePath))
        }

        #expect(violations.isEmpty, "TODO/FIXME markers must be resolved or moved into the audit report:\n\(violations.joined(separator: "\n"))")
    }

    @Test func appSourcesUseNamespacedUserDefaultsKeys() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let files = try Self.swiftFiles(in: appRoot)
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.userDefaultsKeyLiteralViolations(in: source, path: relativePath))
        }

        #expect(violations.isEmpty, "UserDefaults keys must be dot-namespaced:\n\(violations.joined(separator: "\n"))")
    }

    @Test func appSourcesDoNotAccessUserDefaultsStandardDirectly() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let files = try Self.swiftFiles(in: appRoot)
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.userDefaultsStandardViolations(in: source, path: relativePath))
        }

        #expect(violations.isEmpty, "Inject UserDefaults through initializers instead of reading UserDefaults.standard directly:\n\(violations.joined(separator: "\n"))")
    }

    @Test func appSourcesDoNotAccessFileManagerDefaultDirectly() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let files = try Self.swiftFiles(in: appRoot)
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.fileManagerDefaultViolations(in: source, path: relativePath))
        }

        #expect(violations.isEmpty, "Inject FileManager through initializers instead of reading FileManager.default directly:\n\(violations.joined(separator: "\n"))")
    }

    @Test func userDictionaryRequiresExplicitFileManagerBoundary() throws {
        let projectRoot = try #require(Self.projectRoot())
        let file = projectRoot
            .appendingPathComponent("LayoutSwitcher", isDirectory: true)
            .appendingPathComponent("Dictionary", isDirectory: true)
            .appendingPathComponent("UserDictionary.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

        #expect(!sanitizedSource.contains("FileManager = .default"))
        #expect(!sanitizedSource.contains("FileManager.default"))
        #expect(sanitizedSource.contains("convenience init(\n        language: LanguageID,\n        storageURL: URL? = nil,\n        fileManager: FileManager\n    )"))
        #expect(sanitizedSource.contains("private static func fileURL(for language: LanguageID, fileManager: FileManager) -> URL"))
    }

    @Test func presentationModeDetectorDoesNotAccessNSWorkspaceSharedDirectly() throws {
        let projectRoot = try #require(Self.projectRoot())
        let file = projectRoot
            .appendingPathComponent("LayoutSwitcher", isDirectory: true)
            .appendingPathComponent("Pipeline", isDirectory: true)
            .appendingPathComponent("PresentationModeDetector.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
        let violations = Self.nsWorkspaceSharedViolations(in: source, path: relativePath)

        #expect(violations.isEmpty, "Inject NSWorkspace through PresentationModeDetector initializer instead of reading NSWorkspace.shared directly:\n\(violations.joined(separator: "\n"))")
    }

    @Test func presentationModeDetectorRequiresExplicitWorkspaceBoundary() throws {
        let projectRoot = try #require(Self.projectRoot())
        let file = projectRoot
            .appendingPathComponent("LayoutSwitcher", isDirectory: true)
            .appendingPathComponent("Pipeline", isDirectory: true)
            .appendingPathComponent("PresentationModeDetector.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

        #expect(!sanitizedSource.contains("NSWorkspace = .shared"))
        #expect(sanitizedSource.contains("init(\n        workspace: NSWorkspace,\n        presentationBundleIDs: Set<String> = PresentationModeDetector.defaultPresentationBundleIDs\n    )"))
    }

    @Test func focusedAppObserverDoesNotAccessNSWorkspaceSharedDirectly() throws {
        let projectRoot = try #require(Self.projectRoot())
        let file = projectRoot
            .appendingPathComponent("LayoutSwitcher", isDirectory: true)
            .appendingPathComponent("Stats", isDirectory: true)
            .appendingPathComponent("FocusedAppObserver.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
        let violations = Self.nsWorkspaceSharedViolations(in: source, path: relativePath)

        #expect(violations.isEmpty, "Inject NSWorkspace through FocusedAppObserver initializer instead of reading NSWorkspace.shared directly:\n\(violations.joined(separator: "\n"))")
    }

    @Test func focusedAppObserverRequiresExplicitWorkspaceBoundary() throws {
        let projectRoot = try #require(Self.projectRoot())
        let file = projectRoot
            .appendingPathComponent("LayoutSwitcher", isDirectory: true)
            .appendingPathComponent("Stats", isDirectory: true)
            .appendingPathComponent("FocusedAppObserver.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

        #expect(!sanitizedSource.contains("NSWorkspace = .shared"))
        #expect(sanitizedSource.contains("convenience init(\n        workspace: NSWorkspace,\n        roleProvider: (any FocusedRoleProviding)? = nil\n    )"))
    }

    @Test func exclusionListDoesNotAccessNSWorkspaceSharedDirectly() throws {
        let projectRoot = try #require(Self.projectRoot())
        let file = projectRoot
            .appendingPathComponent("LayoutSwitcher", isDirectory: true)
            .appendingPathComponent("Stats", isDirectory: true)
            .appendingPathComponent("ExclusionList.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
        let violations = Self.nsWorkspaceSharedViolations(in: source, path: relativePath)

        #expect(violations.isEmpty, "Inject NSWorkspace through ExclusionList initializer or helper parameter instead of reading NSWorkspace.shared directly:\n\(violations.joined(separator: "\n"))")
    }

    @Test func accessibilityPermissionDoesNotAccessNSWorkspaceSharedDirectly() throws {
        let projectRoot = try #require(Self.projectRoot())
        let file = projectRoot
            .appendingPathComponent("LayoutSwitcher", isDirectory: true)
            .appendingPathComponent("EventTap", isDirectory: true)
            .appendingPathComponent("AccessibilityPermission.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
        let violations = Self.nsWorkspaceSharedViolations(in: source, path: relativePath)

        #expect(violations.isEmpty, "Inject NSWorkspace through AccessibilityPermission initializer instead of reading NSWorkspace.shared directly:\n\(violations.joined(separator: "\n"))")
    }

    @Test func accessibilityPermissionRequiresExplicitWorkspaceBoundary() throws {
        let projectRoot = try #require(Self.projectRoot())
        let file = projectRoot
            .appendingPathComponent("LayoutSwitcher", isDirectory: true)
            .appendingPathComponent("EventTap", isDirectory: true)
            .appendingPathComponent("AccessibilityPermission.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

        #expect(!sanitizedSource.contains("NSWorkspace = .shared"))
        #expect(sanitizedSource.contains("convenience init(\n        pollingInterval: TimeInterval = 1.0,\n        workspace: NSWorkspace\n    )"))
    }

    @Test func helpContentDoesNotAccessBundleMainDirectly() throws {
        let projectRoot = try #require(Self.projectRoot())
        let file = projectRoot
            .appendingPathComponent("LayoutSwitcher", isDirectory: true)
            .appendingPathComponent("UI", isDirectory: true)
            .appendingPathComponent("HelpContent.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
        let violations = Self.bundleMainViolations(in: source, path: relativePath)

        #expect(violations.isEmpty, "Inject Bundle through HelpBodyLoader initializer instead of reading Bundle.main directly:\n\(violations.joined(separator: "\n"))")
    }

    @Test func notificationManagerDoesNotAccessCurrentNotificationCenterDirectly() throws {
        let projectRoot = try #require(Self.projectRoot())
        let file = projectRoot
            .appendingPathComponent("LayoutSwitcher", isDirectory: true)
            .appendingPathComponent("Notifications", isDirectory: true)
            .appendingPathComponent("NotificationManager.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
        let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
        let violations = Self.notificationCenterCurrentViolations(in: sanitizedSource, path: relativePath)

        #expect(violations.isEmpty, "Inject UNUserNotificationCenter through NotificationManager initializer instead of reading UNUserNotificationCenter.current() directly:\n\(violations.joined(separator: "\n"))")
        #expect(!sanitizedSource.contains("UNUserNotificationCenter = .current()"))
        #expect(!sanitizedSource.contains("MakeNotificationID = { UUID().uuidString }"))
        #expect(!sanitizedSource.contains("UUID().uuidString"))
        #expect(!sanitizedSource.contains("content.sound = .default"))
        #expect(sanitizedSource.contains("notificationCenter: UNUserNotificationCenter,\n        makeNotificationID"))
    }

    @Test func secureInputObserverKeepsInitializerDefaultsOnProductionBoundaryOnly() throws {
        let projectRoot = try #require(Self.projectRoot())
        let file = projectRoot
            .appendingPathComponent("LayoutSwitcher", isDirectory: true)
            .appendingPathComponent("EventTap", isDirectory: true)
            .appendingPathComponent("SecureInputObserver.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
        let violations = Self.defaultedInjectedClosureViolations(
            in: source,
            path: relativePath,
            closureNames: ["secureInputStatusProvider", "pollingTimerFactory"]
        )

        #expect(violations.isEmpty, "Keep SecureInputObserver production wiring in the convenience initializer and require explicit DI closures in the testable initializer:\n\(violations.joined(separator: "\n"))")
    }

    @Test func appSourcesCaptureSelfWeaklyInTasks() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let files = try Self.swiftFiles(in: appRoot)
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.taskSelfCaptureViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Task closures capture self without `[weak self]`:\n\(violations.joined(separator: "\n"))")
    }

    @Test func appSourcesPassSensitivityThresholdsToDetectorDecisions() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let files = try Self.swiftFiles(in: appRoot)
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.detectorDecisionThresholdViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Detector decisions must receive sensitivity thresholds:\n\(violations.joined(separator: "\n"))")
    }

    @Test func appSourceCodeOutsideStringsAndCommentsIsASCIIOnly() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let files = try Self.swiftFiles(in: appRoot)
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.nonASCIICodeViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden non-ASCII code outside strings/comments in app sources:\n\(violations.joined(separator: "\n"))")
    }

    @Test func appSourcesUseObservationInsteadOfObservableObject() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let files = try Self.swiftFiles(in: appRoot)
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.observableObjectViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden ObservableObject APIs in app sources:\n\(violations.joined(separator: "\n"))")
    }

    @Test func appSourcesDoNotImportCombine() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let files = try Self.swiftFiles(in: appRoot)
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.combineImportViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden Combine imports in app sources:\n\(violations.joined(separator: "\n"))")
    }

    @Test func appSourcesDoNotImportTestFrameworks() throws {
        let projectRoot = try #require(Self.projectRoot())
        let appRoot = projectRoot.appendingPathComponent("LayoutSwitcher", isDirectory: true)
        let files = try Self.swiftFiles(in: appRoot)
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            let relativePath = file.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            violations.append(contentsOf: Self.testFrameworkImportViolations(in: sanitizedSource, path: relativePath))
        }

        #expect(violations.isEmpty, "Forbidden test framework imports in app sources:\n\(violations.joined(separator: "\n"))")
    }

    @Test func unitTestsDoNotFallbackToStandardUserDefaultsForIsolatedSuites() throws {
        let projectRoot = try #require(Self.projectRoot())
        let testFiles = [
            "AppStateTests.swift",
            "ExclusionListTests.swift",
            "HotkeyCoordinatorTests.swift",
            "HotkeyRegistryTests.swift",
            "LearningCacheTests.swift",
            "PerAppLayoutPreferencesTests.swift",
            "RecentSwitchesTests.swift",
            "TypingPipelineTests.swift"
        ]
        var violations: [String] = []

        for testFile in testFiles {
            let file = projectRoot
                .appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
                .appendingPathComponent(testFile)
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
            if sanitizedSource.contains("UserDefaults.standard") || sanitizedSource.contains("?? .standard") {
                violations.append("LayoutSwitcherTests/\(testFile): use `try #require(UserDefaults(suiteName: ...))` instead of falling back to standard defaults")
            }
        }

        #expect(violations.isEmpty, "Unit tests must not fallback to real UserDefaults.standard for isolated suites:\n\(violations.joined(separator: "\n"))")
    }

    @Test func unitTestsFailFastWhenIsolatedUserDefaultsSuitesCannotBeCreated() throws {
        let projectRoot = try #require(Self.projectRoot())
        let testFiles = [
            "AppStateTests.swift",
            "ExclusionListTests.swift",
            "HotkeyCoordinatorTests.swift",
            "HotkeyRegistryTests.swift",
            "LearningCacheTests.swift",
            "PerAppLayoutPreferencesTests.swift",
            "RecentSwitchesTests.swift",
            "TypingPipelineTests.swift"
        ]
        var violations: [String] = []

        for testFile in testFiles {
            let file = projectRoot
                .appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
                .appendingPathComponent(testFile)
            let source = try String(contentsOf: file, encoding: .utf8)
            let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

            guard sanitizedSource.contains("UserDefaults(suiteName:") else { continue }

            if sanitizedSource.contains("Issue.record") {
                violations.append("LayoutSwitcherTests/\(testFile): use `try #require(UserDefaults(suiteName: ...))` instead of `Issue.record(...)` and early return")
            }

            if sanitizedSource.contains("guard let") {
                violations.append("LayoutSwitcherTests/\(testFile): isolated UserDefaults suite creation should fail fast with `try #require(...)`, not `guard let`")
            }
        }

        #expect(violations.isEmpty, "Unit tests must fail fast when isolated UserDefaults suites cannot be created:\n\(violations.joined(separator: "\n"))")
    }

    @Test func localizationCatalogTestsKeepFileEnumerationInjected() throws {
        let projectRoot = try #require(Self.projectRoot())
        let file = projectRoot
            .appendingPathComponent("LayoutSwitcherTests", isDirectory: true)
            .appendingPathComponent("LocalizationCatalogTests.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

        #expect(!sanitizedSource.contains("FileManager.default"), "LocalizationCatalogTests should inject file enumeration instead of reading FileManager.default directly")
    }

    @Test func swiftSafetyRulesTestsKeepFileEnumerationInjected() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath), encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)

        #expect(!sanitizedSource.contains("FileManager.default"), "SwiftSafetyRulesTests should inject file enumeration instead of reading FileManager.default directly")
    }

    @Test func sanitizerRemovesCommentsAndStringLiteralsBeforeRuleScanning() {
        let fixture = """
        // fatalError("comment-only trap")
        let message = "DispatchQueue.main.async fatalError( ObservableObject print( Thread.sleep( Date() Date.now Calendar.current import Combine import Testing import XCTest"
        /*
        Task.sleep(for: .seconds(1))
        Date()
        Date.now
        Calendar.current
        UUID()
        UUID().uuidString
        Int.random(in: 0...1)
        Task { await work() }
        Task { @MainActor in self.work() }
        detector.decide(buffer: [], activeLanguage: .en)
        @unchecked Sendable
        MainActor.assumeIsolated {}
        nonisolated(unsafe) var cached = 1
        static let shared = Service()
        static var shared = Service()
        static var mutableCache = Cache()
        static let formatter: DateFormatter = DateFormatter()
        static var formatter = DateFormatter()
        static let live = Service()
        final class InMemoryDictionary {}
        final class PresentationModeDetector {}
        final class LearningCache {}
        final class LayoutDetector {}
        final class CompositeDictionary {}
        final class LaunchAtLoginManager {}
        final class SmartPaste {}
        final class SelectionConverter {}
        final class Retyper {}
        class NonFinalReferenceType {}
        @Published var title = ""
        import Combine
        import Testing
        import XCTest
        */
        let safeIdentifier = 1
        """
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: fixture)

        #expect(Self.runtimeTrapViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.consoleLoggingViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.uncontrolledSleepViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.wallClockViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.legacyDispatchQueueViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.explicitActorTaskViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.taskSelfCaptureViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.detectorDecisionThresholdViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.observableObjectViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.combineImportViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.testFrameworkImportViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.randomAPIViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.uncheckedSendableViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.unsafeIsolationBypassViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.singletonSharedStateViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.staticMutableStateViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.staticDateFormatterViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.staticLiveInstanceViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.inMemoryDictionaryReferenceTypeViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.presentationModeDetectorReferenceTypeViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.learningCacheReferenceTypeViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.layoutDetectorReferenceTypeViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.compositeDictionaryReferenceTypeViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.launchAtLoginManagerReferenceTypeViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.smartPasteReferenceTypeViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.selectionConverterReferenceTypeViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.retyperReferenceTypeViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(Self.nonFinalClassViolations(in: sanitizedSource, path: "Fixture.swift").isEmpty)
        #expect(sanitizedSource.contains("safeIdentifier"))
    }

    @Test func sequenceDetectorDoesNotUseTaskSleepDirectly() throws {
        let projectRoot = try #require(Self.projectRoot())
        let relativePath = "LayoutSwitcher/Pipeline/SequenceDetector.swift"
        let file = projectRoot.appendingPathComponent(relativePath)
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
        let violations = Self.uncontrolledSleepViolations(in: sanitizedSource, path: relativePath)

        #expect(violations.isEmpty, "SequenceDetector must receive delay through injected closure:\n\(violations.joined(separator: "\n"))")
    }

    @Test func typingPipelineDoesNotUseTaskSleepDirectly() throws {
        let projectRoot = try #require(Self.projectRoot())
        let relativePath = "LayoutSwitcher/Pipeline/TypingPipeline.swift"
        let file = projectRoot.appendingPathComponent(relativePath)
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
        let violations = Self.uncontrolledSleepViolations(in: sanitizedSource, path: relativePath)

        #expect(violations.isEmpty, "TypingPipeline must receive sequence delay through injected closure:\n\(violations.joined(separator: "\n"))")
    }

    @Test func pipelineTunablesStayExplicitAtPipelineBoundaries() throws {
        let projectRoot = try #require(Self.projectRoot())
        let typingFile = projectRoot.appendingPathComponent("LayoutSwitcher/Pipeline/TypingPipeline.swift")
        let dispatcherFile = projectRoot.appendingPathComponent("LayoutSwitcher/Pipeline/RetypeDispatcher.swift")
        let typingSource = Self.removingCommentsAndStringLiterals(
            from: try String(contentsOf: typingFile, encoding: .utf8)
        )
        let dispatcherSource = Self.removingCommentsAndStringLiterals(
            from: try String(contentsOf: dispatcherFile, encoding: .utf8)
        )

        #expect(!typingSource.contains("PipelineTunables = .default"))
        #expect(!dispatcherSource.contains("PipelineTunables = .default"))
        #expect(!dispatcherSource.contains("Date = Date.init"))
        #expect(typingSource.contains("tunables: PipelineTunables,\n        bundleNameProvider"))
        #expect(dispatcherSource.contains("tunables: PipelineTunables,\n        bundleNameProvider"))
        #expect(dispatcherSource.contains("now: @escaping @MainActor () -> Date\n    )"))
    }

    @Test func manualActionsCoordinatorRequiresExplicitClock() throws {
        let projectRoot = try #require(Self.projectRoot())
        let coordinatorFile = projectRoot.appendingPathComponent("LayoutSwitcher/Pipeline/ManualActionsCoordinator.swift")
        let typingFile = projectRoot.appendingPathComponent("LayoutSwitcher/Pipeline/TypingPipeline.swift")
        let coordinatorSource = Self.removingCommentsAndStringLiterals(
            from: try String(contentsOf: coordinatorFile, encoding: .utf8)
        )
        let typingSource = Self.removingCommentsAndStringLiterals(
            from: try String(contentsOf: typingFile, encoding: .utf8)
        )

        #expect(!coordinatorSource.contains("Date = Date.init"))
        #expect(coordinatorSource.contains("now: @escaping @MainActor () -> Date\n    )"))
        #expect(typingSource.contains("committedHistoryProvider: { historyProvider() },\n            now: now"))
    }

    @Test func retyperDoesNotUseTaskSleepDirectly() throws {
        let projectRoot = try #require(Self.projectRoot())
        let relativePath = "LayoutSwitcher/Mapping/Retyper.swift"
        let file = projectRoot.appendingPathComponent(relativePath)
        let source = try String(contentsOf: file, encoding: .utf8)
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
        let violations = Self.uncontrolledSleepViolations(in: sanitizedSource, path: relativePath)

        #expect(violations.isEmpty, "Retyper must receive layout-confirmation delay through injected closure:\n\(violations.joined(separator: "\n"))")
    }

    @Test func scannersFindForbiddenTokensInCode() {
        #expect(!Self.runtimeTrapViolations(
            in: "fatalError()\npreconditionFailure()\nassertionFailure()\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.consoleLoggingViolations(
            in: "print()\ndebugPrint()\ndump(1)\nNSLog()\nos_log()\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.uncontrolledSleepViolations(
            in: "Thread.sleep(forTimeInterval: 1)\nTask.sleep(for: .seconds(1))\nusleep(1)\nnanosleep(nil, nil)\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.wallClockViolations(
            in: "let now = Date()\nlet currentDate = Date.now\nlet calendar = Calendar.current\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.randomAPIViolations(
            in: "let id = UUID()\nlet value = Int.random(in: 0...1)\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.uncheckedSendableViolations(
            in: "struct UnsafeBox: @unchecked Sendable {}\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.unsafeIsolationBypassViolations(
            in: "MainActor.assumeIsolated {}\nnonisolated(unsafe) var state = 1\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.singletonSharedStateViolations(
            in: "static let shared = Service()\nstatic var shared = Service()\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.staticMutableStateViolations(
            in: "static var cached = Cache()\nprivate static var typedCache: [String: Int] = [:]\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(Self.staticMutableStateViolations(
            in: "static var current: Bool { true }\nfileprivate static var activeLanguage: HelpLanguage { .en }\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.staticDateFormatterViolations(
            in: "private static let timestampFormatter: DateFormatter = DateFormatter()\nstatic var formatter = DateFormatter()\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.staticLiveInstanceViolations(
            in: "static let live = Service()\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.inMemoryDictionaryReferenceTypeViolations(
            in: "final class InMemoryDictionary {}\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.presentationModeDetectorReferenceTypeViolations(
            in: "final class PresentationModeDetector {}\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.learningCacheReferenceTypeViolations(
            in: "final class LearningCache {}\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.layoutDetectorReferenceTypeViolations(
            in: "final class LayoutDetector {}\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.compositeDictionaryReferenceTypeViolations(
            in: "final class CompositeDictionary {}\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.launchAtLoginManagerReferenceTypeViolations(
            in: "final class LaunchAtLoginManager {}\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.smartPasteReferenceTypeViolations(
            in: "final class SmartPaste {}\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.selectionConverterReferenceTypeViolations(
            in: "final class SelectionConverter {}\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.retyperReferenceTypeViolations(
            in: "final class Retyper {}\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.nonFinalClassViolations(
            in: "class MutableReference {}\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(Self.nonFinalClassViolations(
            in: "final class StableReference {}\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.legacyDispatchQueueViolations(
            in: "DispatchQueue.main.async {}\nDispatchQueue.main.asyncAfter(deadline: .now()) {}\nDispatchQueue.global().async {}\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.explicitActorTaskViolations(
            in: "Task { await work() }\nTask(priority: .userInitiated) { await work() }\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(Self.explicitActorTaskViolations(
            in: "Task { @MainActor in await work() }\nTask { @MainActor [weak self] in await self?.work() }\nTask.detached { await work() }\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.loggerInterpolationPrivacyViolations(
            in: #"Self.logger.info("value \(name)")"#,
            path: "Fixture.swift"
        ).isEmpty)
        #expect(Self.loggerInterpolationPrivacyViolations(
            in: #"Self.logger.info("value \(name, privacy: .public)")"#,
            path: "Fixture.swift"
        ).isEmpty)
        #expect(Self.loggerInterpolationPrivacyViolations(
            in: #"Self.logger.info("value \(String(describing: name), privacy: .public)")"#,
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.loggerDeclarationViolations(
            in: #"private static let logger = Logger(subsystem: "Other", category: "Pipeline")"#,
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.loggerDeclarationViolations(
            in: #"private static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "pipeline")"#,
            path: "Fixture.swift"
        ).isEmpty)
        #expect(Self.loggerDeclarationViolations(
            in: #"private static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "Pipeline")"#,
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.todoMarkerViolations(
            in: "// TODO: remove temporary workaround\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.todoMarkerViolations(
            in: "// FIXME: handle edge case\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(Self.todoMarkerViolations(
            in: "// Technical debt is tracked in Swift6CodeQualityAudit.md\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.userDefaultsKeyLiteralViolations(
            in: #"private static let defaultsKey = "enabled""#,
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.userDefaultsKeyLiteralViolations(
            in: #"defaults.set(true, forKey: "enabled")"#,
            path: "Fixture.swift"
        ).isEmpty)
        #expect(Self.userDefaultsKeyLiteralViolations(
            in: #"private static let defaultsKey = "settings.enabled""#,
            path: "Fixture.swift"
        ).isEmpty)
        #expect(Self.userDefaultsKeyLiteralViolations(
            in: #"private static let legacyDefaultsKey = "enabled""#,
            path: "Fixture.swift"
        ).isEmpty)
        #expect(Self.userDefaultsKeyLiteralViolations(
            in: #"private static let prefix = "stats.""#,
            path: "Fixture.swift"
        ).isEmpty)
        #expect(Self.userDefaultsKeyLiteralViolations(
            in: #"defaults.set(value, forKey: Self.prefix + "autoTotal")"#,
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.userDefaultsStandardViolations(
            in: "let defaults = UserDefaults.standard",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(Self.userDefaultsStandardViolations(
            in: "let defaults: UserDefaults = .standard",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.fileManagerDefaultViolations(
            in: "let fileManager = FileManager.default",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(Self.fileManagerDefaultViolations(
            in: "let fileManager: FileManager = .default",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.nsWorkspaceSharedViolations(
            in: "let workspace = NSWorkspace.shared",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(Self.nsWorkspaceSharedViolations(
            in: "let workspace: NSWorkspace = .shared",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.bundleMainViolations(
            in: "let bundle = Bundle.main",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(Self.bundleMainViolations(
            in: "let bundle: Bundle = .main",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.notificationCenterCurrentViolations(
            in: "let center = UNUserNotificationCenter.current()",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(Self.notificationCenterCurrentViolations(
            in: "let center: UNUserNotificationCenter = .current()",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.defaultedInjectedClosureViolations(
            in: "init(clock: Clock = SystemClock()) {}",
            path: "Fixture.swift",
            closureNames: ["clock"]
        ).isEmpty)
        #expect(Self.defaultedInjectedClosureViolations(
            in: "init(clock: Clock) {}",
            path: "Fixture.swift",
            closureNames: ["clock"]
        ).isEmpty)
        #expect(!Self.taskSelfCaptureViolations(
            in: "Task { @MainActor in self.work() }\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(Self.taskSelfCaptureViolations(
            in: "Task { @MainActor [weak self] in await self?.work() }\nTask { @MainActor in await work() }\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.detectorDecisionThresholdViolations(
            in: "let decision = detector.decide(\n    buffer: word.characters,\n    activeLanguage: activeLanguage\n)\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(Self.detectorDecisionThresholdViolations(
            in: "let decision = detector.decide(\n    buffer: word.characters,\n    activeLanguage: activeLanguage,\n    thresholds: currentDetectionThresholds\n)\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.xctestViolations(
            in: "import XCTest\nXCTAssert(true)\nXCTFail()\nXCTUnwrap(value)\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.observableObjectViolations(
            in: "@Published var title = \"\"\nfinal class Model: ObservableObject {}\nlet _ = objectWillChange\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.combineImportViolations(
            in: "import Combine\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.testFrameworkImportViolations(
            in: "import Testing\nimport XCTest\n",
            path: "Fixture.swift"
        ).isEmpty)
        #expect(!Self.nonASCIICodeViolations(
            in: "let привіт = 1",
            path: "Fixture.swift"
        ).isEmpty)
    }

    @Test func scannerIgnoresPrefixNegationAndFindsForceOperations() {
        let source = """
        #expect(!title.isEmpty)
        guard !flag else { return }
        if !(flag || other) { return }
        optional!
        try! risky()
        value as! String
        """
        let sanitizedSource = Self.removingCommentsAndStringLiterals(from: source)
        let violations = Self.forceOperationViolations(in: sanitizedSource, path: "Fixture.swift")

        #expect(violations == [
            "Fixture.swift:4: avoid force unwrap",
            "Fixture.swift:5: avoid `try!`",
            "Fixture.swift:6: avoid `as!`"
        ])
    }

    private static func projectRoot() -> URL? {
        var current = URL(fileURLWithPath: #filePath)
        while current.lastPathComponent != "LayoutSwitcherTests" {
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { return nil }
            current = parent
        }
        return current.deletingLastPathComponent()
    }

    private static func swiftFiles(in directory: URL) throws -> [URL] {
        try Self.swiftFiles(in: directory, enumerateFiles: Self.enumerateFiles)
    }

    private static func swiftFiles(
        in directory: URL,
        enumerateFiles: FileEnumerator
    ) throws -> [URL] {
        guard let enumerator = enumerateFiles(
            directory,
            [.isRegularFileKey],
            [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            files.append(file)
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func enumerateFiles(
        at root: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options: FileManager.DirectoryEnumerationOptions
    ) -> FileManager.DirectoryEnumerator? {
        FileManager().enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: options
        )
    }

    private static func forceOperationViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.forceOperationViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func runtimeTrapViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.runtimeTrapViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func forceOperationViolations(in line: String) -> [String] {
        var violations: [String] = []
        let characters = Array(line)

        if line.contains("try!") || line.contains("try !") {
            violations.append("avoid `try!`")
        }

        if line.contains("as!") || line.contains("as !") {
            violations.append("avoid `as!`")
        }

        for index in characters.indices where characters[index] == "!" {
            guard index > characters.startIndex else { continue }
            let previous = characters[index - 1]
            let next = Self.nextNonWhitespace(in: characters, after: index)
            let tokenBeforeBang = String(characters[..<index]).trimmingCharacters(in: .whitespaces)
            guard !previous.isWhitespace else { continue }
            guard previous.isLetter || previous.isNumber || previous == "_" || previous == ")" || previous == "]" else {
                continue
            }
            guard previous != "=", previous != "!", previous != "<", previous != ">" else { continue }
            guard next != "=" else { continue }
            guard !tokenBeforeBang.hasSuffix("try"), !tokenBeforeBang.hasSuffix("as") else { continue }
            violations.append("avoid force unwrap")
        }

        return violations
    }

    private static func runtimeTrapViolations(in line: String) -> [String] {
        [
            ("fatalError(", "avoid `fatalError`"),
            ("preconditionFailure(", "avoid `preconditionFailure`"),
            ("assertionFailure(", "avoid `assertionFailure`")
        ].compactMap { token, message in
            line.contains(token) ? message : nil
        }
    }

    private static func uncontrolledSleepViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.uncontrolledSleepViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func uncontrolledSleepViolations(in line: String) -> [String] {
        [
            ("Thread.sleep(", "avoid `Thread.sleep`"),
            ("Task.sleep(", "avoid `Task.sleep`"),
            ("Task<Never, Never>.sleep(", "avoid `Task<Never, Never>.sleep`"),
            ("usleep(", "avoid `usleep`"),
            ("nanosleep(", "avoid `nanosleep`")
        ].compactMap { token, message in
            line.contains(token) ? message : nil
        }
    }

    private static func wallClockViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.wallClockViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func wallClockViolations(in line: String) -> [String] {
        [
            ("Date()", "inject fixed dates instead of using `Date()`"),
            ("Date.now", "inject fixed dates instead of using `Date.now`"),
            ("Calendar.current", "inject fixed calendars instead of using `Calendar.current`")
        ].compactMap { token, message in
            line.contains(token) ? message : nil
        }
    }

    private static func randomAPIViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.randomAPIViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func randomAPIViolations(in line: String) -> [String] {
        var violations: [String] = []

        if line.contains("UUID().uuidString") {
            violations.append("inject fixed identifiers instead of using `UUID().uuidString`")
        } else if line.contains("UUID()") {
            violations.append("inject fixed identifiers instead of using `UUID()`")
        }

        if line.contains(".random(") {
            violations.append("inject fixed values instead of using random APIs")
        }

        return violations
    }

    private static func randomUserDefaultsSuiteNameViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line -> [String] in
                guard line.contains("UserDefaults(suiteName:"),
                      line.contains("UUID().uuidString")
                else {
                    return []
                }
                return ["\(path):\(index + 1): use deterministic suite names for isolated UserDefaults, e.g. `#function`"]
            }
    }

    private static func uncheckedSendableViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.uncheckedSendableViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func uncheckedSendableViolations(in line: String) -> [String] {
        line.contains("@unchecked Sendable")
            ? ["avoid `@unchecked Sendable`; prefer actor isolation, value semantics, or an audited wrapper"]
            : []
    }

    private static func unsafeIsolationBypassViolations(in source: String, path: String) -> [String] {
        let violations = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.unsafeIsolationBypassViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }

        if path == "LayoutSwitcher/EventTap/KeyboardEventTap.swift",
           violations.count == 1,
           violations.first?.contains("MainActor.assumeIsolated") == true {
            return []
        }

        return violations
    }

    private static func unsafeIsolationBypassViolations(in line: String) -> [String] {
        [
            ("MainActor.assumeIsolated", "avoid `MainActor.assumeIsolated`; prefer explicit `@MainActor` isolation"),
            ("nonisolated(unsafe)", "avoid `nonisolated(unsafe)`; prefer actor isolation or immutable state")
        ].compactMap { token, message in
            line.contains(token) ? message : nil
        }
    }

    private static func singletonSharedStateViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.singletonSharedStateViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func singletonSharedStateViolations(in line: String) -> [String] {
        let pattern = #"static\s+(let|var)\s+shared\b"#
        return line.range(of: pattern, options: .regularExpression) == nil
            ? []
            : ["avoid singleton `shared` state; inject dependencies through initializers or closures"]
    }

    private static func staticMutableStateViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.staticMutableStateViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func staticMutableStateViolations(in line: String) -> [String] {
        let pattern = #"\bstatic\s+var\s+[A-Za-z_][A-Za-z0-9_]*\s*(?::[^=\n]+)?="#
        return line.range(of: pattern, options: .regularExpression) == nil
            ? []
            : ["avoid stored `static var`; prefer instance state, immutable `static let`, or injected caches"]
    }

    private static func staticDateFormatterViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.staticDateFormatterViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func staticDateFormatterViolations(in line: String) -> [String] {
        let patterns = [
            #"\bstatic\s+(let|var)\s+[A-Za-z_][A-Za-z0-9_]*\s*:\s*DateFormatter\b"#,
            #"\bstatic\s+(let|var)\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*DateFormatter\("#
        ]
        return patterns.contains { line.range(of: $0, options: .regularExpression) != nil }
            ? ["avoid static `DateFormatter`; it is mutable reference state, prefer injected formatting or short-lived formatters"]
            : []
    }

    private static func staticLiveInstanceViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.staticLiveInstanceViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func staticLiveInstanceViolations(in line: String) -> [String] {
        let pattern = #"\bstatic\s+let\s+live\b"#
        return line.range(of: pattern, options: .regularExpression) == nil
            ? []
            : ["avoid static `live` instances; use a factory method and inject the returned dependency"]
    }

    private static func inMemoryDictionaryReferenceTypeViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.inMemoryDictionaryReferenceTypeViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func inMemoryDictionaryReferenceTypeViolations(in line: String) -> [String] {
        let pattern = #"\b(final\s+)?class\s+InMemoryDictionary\b"#
        return line.range(of: pattern, options: .regularExpression) == nil
            ? []
            : ["keep `InMemoryDictionary` value-typed; static dictionary caches must not share reference state"]
    }

    private static func presentationModeDetectorReferenceTypeViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.presentationModeDetectorReferenceTypeViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func presentationModeDetectorReferenceTypeViolations(in line: String) -> [String] {
        let pattern = #"\b(final\s+)?class\s+PresentationModeDetector\b"#
        return line.range(of: pattern, options: .regularExpression) == nil
            ? []
            : ["keep `PresentationModeDetector` value-typed; it has no mutable identity"]
    }

    private static func learningCacheReferenceTypeViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.learningCacheReferenceTypeViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func learningCacheReferenceTypeViolations(in line: String) -> [String] {
        let pattern = #"\b(final\s+)?class\s+LearningCache\b"#
        return line.range(of: pattern, options: .regularExpression) == nil
            ? []
            : ["keep `LearningCache` value-typed; persistence is injected and identity is unnecessary"]
    }

    private static func layoutDetectorReferenceTypeViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.layoutDetectorReferenceTypeViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func layoutDetectorReferenceTypeViolations(in line: String) -> [String] {
        let pattern = #"\b(final\s+)?class\s+LayoutDetector\b"#
        return line.range(of: pattern, options: .regularExpression) == nil
            ? []
            : ["keep `LayoutDetector` value-typed; detection is pure and thresholds are immutable"]
    }

    private static func compositeDictionaryReferenceTypeViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.compositeDictionaryReferenceTypeViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func compositeDictionaryReferenceTypeViolations(in line: String) -> [String] {
        let pattern = #"\b(final\s+)?class\s+CompositeDictionary\b"#
        return line.range(of: pattern, options: .regularExpression) == nil
            ? []
            : ["keep `CompositeDictionary` value-typed; it only layers immutable dictionary parts"]
    }

    private static func launchAtLoginManagerReferenceTypeViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.launchAtLoginManagerReferenceTypeViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func launchAtLoginManagerReferenceTypeViolations(in line: String) -> [String] {
        let pattern = #"\b(final\s+)?class\s+LaunchAtLoginManager\b"#
        return line.range(of: pattern, options: .regularExpression) == nil
            ? []
            : ["keep `LaunchAtLoginManager` value-typed; side effects are injected and identity is unnecessary"]
    }

    private static func smartPasteReferenceTypeViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.smartPasteReferenceTypeViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func smartPasteReferenceTypeViolations(in line: String) -> [String] {
        let pattern = #"\b(final\s+)?class\s+SmartPaste\b"#
        return line.range(of: pattern, options: .regularExpression) == nil
            ? []
            : ["keep `SmartPaste` value-typed; paste side effects are injected and identity is unnecessary"]
    }

    private static func selectionConverterReferenceTypeViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.selectionConverterReferenceTypeViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func selectionConverterReferenceTypeViolations(in line: String) -> [String] {
        let pattern = #"\b(final\s+)?class\s+SelectionConverter\b"#
        return line.range(of: pattern, options: .regularExpression) == nil
            ? []
            : ["keep `SelectionConverter` value-typed; conversion side effects are injected and identity is unnecessary"]
    }

    private static func retyperReferenceTypeViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.retyperReferenceTypeViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func retyperReferenceTypeViolations(in line: String) -> [String] {
        let pattern = #"\b(final\s+)?class\s+Retyper\b"#
        return line.range(of: pattern, options: .regularExpression) == nil
            ? []
            : ["keep `Retyper` value-typed; retype side effects are injected and identity lives in collaborators"]
    }

    private static func nonFinalClassViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.nonFinalClassViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func nonFinalClassViolations(in line: String) -> [String] {
        let classPattern = #"\bclass\s+[A-Za-z_][A-Za-z0-9_]*\b"#
        guard line.range(of: classPattern, options: .regularExpression) != nil else {
            return []
        }

        let finalClassPattern = #"\bfinal\s+class\s+[A-Za-z_][A-Za-z0-9_]*\b"#
        guard line.range(of: finalClassPattern, options: .regularExpression) == nil else {
            return []
        }

        return ["reference types must be declared `final`; prefer `struct` unless identity is required"]
    }

    private static func xctestViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.xctestViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func xctestViolations(in line: String) -> [String] {
        [
            ("import XCTest", "use Swift Testing instead of XCTest"),
            ("XCTAssert", "use `#expect` instead of `XCTAssert`"),
            ("XCTFail", "use Swift Testing expectations instead of `XCTFail`"),
            ("XCTUnwrap", "use `#require` instead of `XCTUnwrap`")
        ].compactMap { token, message in
            line.contains(token) ? message : nil
        }
    }

    private static func consoleLoggingViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.consoleLoggingViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func consoleLoggingViolations(in line: String) -> [String] {
        [
            ("print(", "use `Logger` instead of `print`"),
            ("Swift.print(", "use `Logger` instead of `Swift.print`"),
            ("debugPrint(", "use `Logger` instead of `debugPrint`"),
            ("dump(", "use `Logger` instead of `dump`"),
            ("NSLog(", "use `Logger` instead of `NSLog`"),
            ("os_log(", "use `Logger` instead of `os_log`")
        ].compactMap { token, message in
            line.contains(token) ? message : nil
        }
    }

    private static func legacyDispatchQueueViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.legacyDispatchQueueViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func legacyDispatchQueueViolations(in line: String) -> [String] {
        [
            ("DispatchQueue.main.async", "use `Task { @MainActor ... }` or direct main-actor isolation"),
            ("DispatchQueue.main.asyncAfter", "use an injected clock or async delay instead of GCD scheduling"),
            ("DispatchQueue.global(", "avoid global queues; prefer structured concurrency"),
            ("DispatchQueue.global().async", "avoid global queues; prefer structured concurrency")
        ].compactMap { token, message in
            line.contains(token) ? message : nil
        }
    }

    private static func explicitActorTaskViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.explicitActorTaskViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func explicitActorTaskViolations(in line: String) -> [String] {
        let taskPattern = #"\bTask\s*(?:\([^)]*\))?\s*\{"#
        let actorPattern = #"\{\s*@[A-Za-z_][A-Za-z0-9_]*(?:\s|\[|in)"#

        guard line.range(of: taskPattern, options: .regularExpression) != nil else {
            return []
        }

        return line.range(of: actorPattern, options: .regularExpression) == nil
            ? ["make unstructured `Task` actor explicit; use `Task { @MainActor in ... }` or inject async work"]
            : []
    }

    private static func loggerInterpolationPrivacyViolations(in source: String, path: String) -> [String] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var violations: [String] = []

        for (offset, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//"),
                  line.contains("logger."),
                  line.contains(#"\("#)
            else {
                continue
            }

            let hasMissingPrivacy = Self.stringInterpolationBodies(in: line).contains { body in
                !body.contains("privacy:")
            }
            if hasMissingPrivacy {
                violations.append("\(path):\(offset + 1): declare logger interpolation privacy")
            }
        }

        return violations
    }

    private static func stringInterpolationBodies(in text: String) -> [String] {
        let characters = Array(text)
        var bodies: [String] = []
        var index = 0

        while index < characters.count {
            guard characters[index] == "\\",
                  index + 1 < characters.count,
                  characters[index + 1] == "("
            else {
                index += 1
                continue
            }

            index += 2
            var depth = 1
            var body = ""
            while index < characters.count && depth > 0 {
                let character = characters[index]
                if character == "(" {
                    depth += 1
                    body.append(character)
                } else if character == ")" {
                    depth -= 1
                    if depth > 0 {
                        body.append(character)
                    }
                } else {
                    body.append(character)
                }
                index += 1
            }

            if depth == 0 {
                bodies.append(body)
            }
        }

        return bodies
    }

    private static func loggerDeclarationViolations(in source: String, path: String) -> [String] {
        let loggerPattern = #"Logger\s*\(\s*subsystem:\s*"([^"]+)"\s*,\s*category:\s*"([^"]+)""#
        let categoryPattern = #"^[A-Z][A-Za-z0-9]*$"#

        return source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { index, line in
                let text = String(line)
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"),
                      let match = text.range(of: loggerPattern, options: .regularExpression)
                else {
                    return nil
                }

                let declaration = String(text[match])
                let parts = declaration
                    .split(separator: "\"", omittingEmptySubsequences: false)
                    .map(String.init)
                guard parts.count >= 4 else {
                    return "\(path):\(index + 1): malformed Logger declaration"
                }

                let subsystem = parts[1]
                let category = parts[3]
                if subsystem != "GIH.LayoutSwitcher" {
                    return "\(path):\(index + 1): Logger subsystem must be GIH.LayoutSwitcher"
                }
                if category.range(of: categoryPattern, options: .regularExpression) == nil {
                    return "\(path):\(index + 1): Logger category must be PascalCase"
                }
                return nil
            }
    }

    private static func todoMarkerViolations(in source: String, path: String) -> [String] {
        let markerPattern = #"\b(TODO|FIXME)\b"#
        return source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { index, line in
                String(line).range(of: markerPattern, options: .regularExpression) == nil
                    ? nil
                    : "\(path):\(index + 1): resolve TODO/FIXME or document it in the audit report"
            }
    }

    private static func userDefaultsKeyLiteralViolations(in source: String, path: String) -> [String] {
        var violations: [String] = []
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for (offset, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//") else { continue }

            if let directKey = Self.stringLiteral(after: "forKey:", in: line),
               !Self.usesNamespacedPrefixForUserDefaultsKey(in: line),
               !Self.isNamespacedUserDefaultsKey(directKey) {
                violations.append("\(path):\(offset + 1): direct UserDefaults key must be dot-namespaced")
            }

            guard let staticName = Self.staticStringMemberName(in: line),
                  Self.looksLikeUserDefaultsKeyConstant(staticName),
                  let staticValue = Self.firstStringLiteral(in: line)
            else {
                continue
            }

            let allowsPrefix = staticName == "prefix"
            if !Self.isNamespacedUserDefaultsKey(staticValue, allowsTrailingDot: allowsPrefix) {
                violations.append("\(path):\(offset + 1): UserDefaults key constant `\(staticName)` must be dot-namespaced")
            }
        }

        return violations
    }

    private static func userDefaultsStandardViolations(in source: String, path: String) -> [String] {
        var violations: [String] = []
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for (offset, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//") else { continue }

            if line.contains("UserDefaults.standard") {
                violations.append("\(path):\(offset + 1): UserDefaults.standard must be injected")
            }
        }

        return violations
    }

    private static func fileManagerDefaultViolations(in source: String, path: String) -> [String] {
        var violations: [String] = []
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for (offset, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//") else { continue }

            if line.contains("FileManager.default") {
                violations.append("\(path):\(offset + 1): FileManager.default must be injected")
            }
        }

        return violations
    }

    private static func nsWorkspaceSharedViolations(in source: String, path: String) -> [String] {
        var violations: [String] = []
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for (offset, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//") else { continue }

            if line.contains("NSWorkspace.shared") {
                violations.append("\(path):\(offset + 1): NSWorkspace.shared must be injected")
            }
        }

        return violations
    }

    private static func bundleMainViolations(in source: String, path: String) -> [String] {
        var violations: [String] = []
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for (offset, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//") else { continue }

            if line.contains("Bundle.main") {
                violations.append("\(path):\(offset + 1): Bundle.main must be injected")
            }
        }

        return violations
    }

    private static func notificationCenterCurrentViolations(in source: String, path: String) -> [String] {
        var violations: [String] = []
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for (offset, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//") else { continue }

            if line.contains("UNUserNotificationCenter.current()") {
                violations.append("\(path):\(offset + 1): UNUserNotificationCenter.current() must be injected")
            }
        }

        return violations
    }

    private static func defaultedInjectedClosureViolations(
        in source: String,
        path: String,
        closureNames: [String]
    ) -> [String] {
        var violations: [String] = []
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for (offset, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//") else { continue }

            for closureName in closureNames where line.contains("\(closureName):") && line.contains("=") {
                violations.append("\(path):\(offset + 1): injected closure \(closureName) must not have a production default")
            }
        }

        return violations
    }

    private static func looksLikeUserDefaultsKeyConstant(_ name: String) -> Bool {
        if name == "legacyDefaultsKey" { return false }
        if name.hasSuffix("PayloadKey") { return false }
        if name.hasSuffix("EnvironmentKey") { return false }
        if name == "prefix" { return true }
        return name == "defaultsKey" || name.hasSuffix("DefaultsKey") || name.hasSuffix("Key")
    }

    private static func isNamespacedUserDefaultsKey(_ key: String, allowsTrailingDot: Bool = false) -> Bool {
        guard key.contains("."), !key.hasPrefix(".") else { return false }
        return allowsTrailingDot || !key.hasSuffix(".")
    }

    private static func stringLiteral(after token: String, in text: String) -> String? {
        guard let tokenRange = text.range(of: token) else { return nil }
        return Self.firstStringLiteral(in: String(text[tokenRange.upperBound...]))
    }

    private static func usesNamespacedPrefixForUserDefaultsKey(in text: String) -> Bool {
        guard let tokenRange = text.range(of: "forKey:") else { return false }
        let suffix = text[tokenRange.upperBound...]
        guard let quoteIndex = suffix.firstIndex(of: "\"") else { return false }
        return suffix[..<quoteIndex].contains("Self.prefix")
    }

    private static func firstStringLiteral(in text: String) -> String? {
        let parts = text.split(separator: "\"", omittingEmptySubsequences: false).map(String.init)
        return parts.count >= 3 ? parts[1] : nil
    }

    private static func staticStringMemberName(in text: String) -> String? {
        let letToken = "static let "
        let varToken = "static var "
        let start: String.Index?
        if let range = text.range(of: letToken) {
            start = range.upperBound
        } else if let range = text.range(of: varToken) {
            start = range.upperBound
        } else {
            start = nil
        }

        guard let start else { return nil }
        let name = text[start...].prefix { character in
            character.isLetter || character.isNumber || character == "_"
        }
        return name.isEmpty ? nil : String(name)
    }

    private static func taskSelfCaptureViolations(in source: String, path: String) -> [String] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let taskPattern = #"\bTask\s*(?:\([^)]*\))?\s*\{"#
        var violations: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            guard line.range(of: taskPattern, options: .regularExpression) != nil else {
                index += 1
                continue
            }

            let startLine = index + 1
            var block = ""
            var depth = 0
            var sawOpeningBrace = false

            repeat {
                let currentLine = lines[index]
                block += currentLine + "\n"
                for character in currentLine {
                    if character == "{" {
                        depth += 1
                        sawOpeningBrace = true
                    } else if character == "}", sawOpeningBrace {
                        depth -= 1
                    }
                }
                index += 1
            } while index < lines.count && (!sawOpeningBrace || depth > 0)

            let capturesSelf = block.contains("self.") || block.contains("self?")
            let weakSelfPattern = #"\[[^\]]*\bweak\s+self\b[^\]]*\]"#
            let capturesWeakSelf = block.range(of: weakSelfPattern, options: .regularExpression) != nil
            if capturesSelf && !capturesWeakSelf {
                violations.append("\(path):\(startLine): capture `self` weakly in Task closures")
            }
        }

        return violations
    }

    private static func detectorDecisionThresholdViolations(in source: String, path: String) -> [String] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var violations: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            guard line.contains("detector.decide(") else {
                index += 1
                continue
            }

            let startLine = index + 1
            var block = ""
            var depth = 0
            var sawOpeningParenthesis = false

            repeat {
                let currentLine = lines[index]
                block += currentLine + "\n"
                for character in currentLine {
                    if character == "(" {
                        depth += 1
                        sawOpeningParenthesis = true
                    } else if character == ")" {
                        depth -= 1
                    }
                }
                index += 1
            } while index < lines.count && (!sawOpeningParenthesis || depth > 0)

            if !block.contains("thresholds:") {
                violations.append("\(path):\(startLine): pass `appState.detectionSensitivity.thresholds` into detector decisions")
            }
        }

        return violations
    }

    private static func nonASCIICodeViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.nonASCIICodeViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func nonASCIICodeViolations(in line: String) -> [String] {
        line.unicodeScalars.contains { scalar in
            scalar.value > 127
        } ? ["keep code identifiers, comments, and logs English-only; localize user-facing text"] : []
    }

    private static func observableObjectViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.observableObjectViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func observableObjectViolations(in line: String) -> [String] {
        [
            ("ObservableObject", "use `@Observable` instead of `ObservableObject`"),
            ("@ObservedObject", "use `@Bindable` or direct observable state instead of `@ObservedObject`"),
            ("@StateObject", "use `@State` with an `@Observable` model instead of `@StateObject`"),
            ("@EnvironmentObject", "avoid implicit `@EnvironmentObject`; inject observable state explicitly"),
            ("@Published", "use `@Observable` stored properties instead of `@Published`"),
            ("objectWillChange", "avoid manual ObservableObject notifications")
        ].compactMap { token, message in
            line.contains(token) ? message : nil
        }
    }

    private static func combineImportViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.combineImportViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func combineImportViolations(in line: String) -> [String] {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmedLine == "import Combine"
            ? ["avoid Combine; prefer Observation and structured concurrency"]
            : []
    }

    private static func testFrameworkImportViolations(in source: String, path: String) -> [String] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .flatMap { index, line in
                Self.testFrameworkImportViolations(in: String(line)).map { "\(path):\(index + 1): \($0)" }
            }
    }

    private static func testFrameworkImportViolations(in line: String) -> [String] {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

        switch trimmedLine {
        case "import Testing":
            return ["do not import Swift Testing in app sources"]
        case "import XCTest":
            return ["do not import XCTest in app sources"]
        default:
            return []
        }
    }

    private static func nextNonWhitespace(in characters: [Character], after index: Int) -> Character? {
        var cursor = index + 1
        while cursor < characters.endIndex {
            let character = characters[cursor]
            if !character.isWhitespace {
                return character
            }
            cursor += 1
        }
        return nil
    }

    private static func removingCommentsAndStringLiterals(from source: String) -> String {
        var result = ""
        var index = source.startIndex
        var state = ScanState.code

        while index < source.endIndex {
            switch state {
            case .code:
                if source[index...].hasPrefix("//") {
                    result.append("  ")
                    source.formIndex(&index, offsetBy: 2)
                    state = .lineComment
                } else if source[index...].hasPrefix("/*") {
                    result.append("  ")
                    source.formIndex(&index, offsetBy: 2)
                    state = .blockComment
                } else if source[index...].hasPrefix("\"\"\"") {
                    result.append("   ")
                    source.formIndex(&index, offsetBy: 3)
                    state = .multilineString
                } else if source[index] == "\"" {
                    result.append(" ")
                    source.formIndex(after: &index)
                    state = .string
                } else {
                    result.append(source[index])
                    source.formIndex(after: &index)
                }
            case .lineComment:
                if source[index].isNewline {
                    result.append(source[index])
                    state = .code
                } else {
                    result.append(" ")
                }
                source.formIndex(after: &index)
            case .blockComment:
                if source[index...].hasPrefix("*/") {
                    result.append("  ")
                    source.formIndex(&index, offsetBy: 2)
                    state = .code
                } else {
                    result.append(source[index].isNewline ? source[index] : " ")
                    source.formIndex(after: &index)
                }
            case .string:
                if source[index] == "\\" {
                    result.append(" ")
                    source.formIndex(after: &index)
                    if index < source.endIndex {
                        result.append(source[index].isNewline ? source[index] : " ")
                        source.formIndex(after: &index)
                    }
                } else if source[index] == "\"" {
                    result.append(" ")
                    source.formIndex(after: &index)
                    state = .code
                } else {
                    result.append(source[index].isNewline ? source[index] : " ")
                    source.formIndex(after: &index)
                }
            case .multilineString:
                if source[index...].hasPrefix("\"\"\"") {
                    result.append("   ")
                    source.formIndex(&index, offsetBy: 3)
                    state = .code
                } else {
                    result.append(source[index].isNewline ? source[index] : " ")
                    source.formIndex(after: &index)
                }
            }
        }

        return result
    }

    private enum ScanState {
        case code
        case lineComment
        case blockComment
        case string
        case multilineString
    }
}
