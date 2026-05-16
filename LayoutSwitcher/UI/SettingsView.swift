import SwiftUI
import UniformTypeIdentifiers
import os

/// Root preferences view grouping all settings tabs.
struct SettingsView: View {
    /// Shared application settings and runtime state.
    @Bindable var appState: AppState
    /// Per-application exclusion list model.
    @Bindable var exclusions: ExclusionList
    /// Usage statistics model rendered in the General tab.
    @Bindable var stats: UsageStats
    /// User-maintained English dictionary.
    @Bindable var userEnglish: UserDictionary
    /// User-maintained Russian dictionary.
    @Bindable var userRussian: UserDictionary
    /// User-maintained Ukrainian dictionary.
    @Bindable var userUkrainian: UserDictionary
    /// User-maintained Romanian dictionary.
    @Bindable var userRomanian: UserDictionary
    /// Current and enabled system keyboard input sources.
    @Bindable var inputSources: InputSourceManager
    /// Hotkey binding registry.
    @Bindable var hotkeys: HotkeyRegistry
    /// Per-application preferred layout settings.
    @Bindable var perAppLayouts: PerAppLayoutPreferences
    /// Recent automatic/manual correction history.
    @Bindable var recents: RecentSwitches
    /// Learned corrections cache shown in the learning tab.
    let learningCache: LearningCache
    /// Launch-at-login side-effect service used by the General tab.
    let launchAtLoginManager: LaunchAtLoginManager
    /// Opens the help window from the settings toolbar.
    let openHelp: () -> Void

    /// Renders tabbed settings UI with a top toolbar exposing the help shortcut.
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: openHelp) {
                    Label(String(localized: "settings.button.help"), systemImage: "questionmark.circle")
                }
                .controlSize(.regular)
                .help(String(localized: "settings.button.help.tooltip"))
                .keyboardShortcut("?", modifiers: [.command])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            tabs
        }
        .frame(width: 820, height: 700)
    }

    /// Tab container that wires each settings model into its dedicated pane.
    private var tabs: some View {
        TabView {
            GeneralTab(appState: appState, stats: stats, launchAtLoginManager: launchAtLoginManager)
                .tabItem { Label(String(localized: "settings.tab.general"), systemImage: "gearshape") }

            LayoutsTab(appState: appState, inputSources: inputSources)
                .tabItem { Label(String(localized: "settings.tab.layouts"), systemImage: "globe") }

            PerAppLayoutsTab(preferences: perAppLayouts, inputSources: inputSources)
                .tabItem { Label(String(localized: "settings.tab.per-app-layouts"), systemImage: "keyboard.badge.ellipsis") }

            HotkeysTab(registry: hotkeys)
                .tabItem { Label(String(localized: "settings.tab.hotkeys"), systemImage: "command") }

            ExclusionsTab(exclusions: exclusions)
                .tabItem { Label(String(localized: "settings.tab.exclusions"), systemImage: "nosign") }

            DictionariesTab(english: userEnglish, russian: userRussian, ukrainian: userUkrainian, romanian: userRomanian)
                .tabItem { Label(String(localized: "settings.tab.dictionaries"), systemImage: "character.book.closed") }

            LearningTab(learningCache: learningCache)
                .tabItem { Label(String(localized: "settings.tab.learned-exceptions"), systemImage: "graduationcap") }

            HistoryTab(recents: recents)
                .tabItem { Label(String(localized: "settings.tab.history"), systemImage: "clock.arrow.circlepath") }

            AboutTab()
                .tabItem { Label(String(localized: "settings.tab.about"), systemImage: "info.circle") }
        }
    }
}

/// General settings tab containing status, detector toggles, and statistics.
private struct GeneralTab: View {
    /// Shared application settings and runtime status.
    @Bindable var appState: AppState
    /// Usage statistics rendered in daily and all-time sections.
    @Bindable var stats: UsageStats
    /// Launch-at-login side-effect service.
    let launchAtLoginManager: LaunchAtLoginManager

    /// Builds grouped form with runtime status and persisted preference controls.
    var body: some View {
        Form {
            Section(String(localized: "settings.section.status")) {
                Toggle(String(localized: "settings.toggle.enable"), isOn: $appState.isEnabled)
                LabeledContent(String(localized: "settings.label.current-layout"), value: appState.currentLayoutID ?? "—")
                LabeledContent(String(localized: "settings.label.accessibility"), value: appState.isAccessibilityGranted ? String(localized: "settings.value.granted") : String(localized: "settings.value.not-granted"))
                LabeledContent(String(localized: "settings.label.last-action"), value: appState.lastActionDescription ?? "—")
                Toggle(String(localized: "settings.toggle.launch-at-login"), isOn: Binding(
                    get: { appState.launchAtLogin },
                    set: { newValue in
                        let success = launchAtLoginManager.setEnabled(newValue)
                        if success {
                            appState.launchAtLogin = newValue
                        }
                    }
                ))
            }

            Section(String(localized: "settings.section.detection")) {
                Toggle(String(localized: "settings.toggle.auto-diacritics"), isOn: $appState.autoAddRomanianDiacritics)
                    .accessibilityIdentifier("settings.toggle.auto-diacritics")
                Toggle(String(localized: "settings.toggle.auto-russian-yo"), isOn: $appState.autoAddRussianYo)
                    .accessibilityIdentifier("settings.toggle.auto-russian-yo")
                Toggle(String(localized: "settings.toggle.correct-double-capitals"), isOn: $appState.correctDoubleCapitals)
                    .accessibilityIdentifier("settings.toggle.correct-double-capitals")
                Toggle(String(localized: "settings.toggle.correct-duplicate-letters"), isOn: $appState.correctDuplicateLetters)
                    .accessibilityIdentifier("settings.toggle.correct-duplicate-letters")
                Toggle(String(localized: "settings.toggle.correct-common-typos"), isOn: $appState.correctCommonTypos)
                    .accessibilityIdentifier("settings.toggle.correct-common-typos")
                Toggle(String(localized: "settings.toggle.correct-single-char"), isOn: $appState.correctSingleCharacterWords)
                    .accessibilityIdentifier("settings.toggle.correct-single-char")
                Toggle(String(localized: "settings.toggle.auto-extend-recent"), isOn: $appState.autoExtendRecentAmbiguous)
                    .accessibilityIdentifier("settings.toggle.auto-extend-recent")
                Picker(String(localized: "settings.picker.aggressiveness"), selection: $appState.detectionSensitivity) {
                    ForEach(DetectionSensitivity.allCases, id: \.self) { sensitivity in
                        Text(sensitivity.localizedTitle).tag(sensitivity)
                    }
                }
                Picker(String(localized: "settings.picker.snooze-duration"), selection: $appState.snoozeDuration) {
                    ForEach(SnoozeDuration.allCases, id: \.self) { duration in
                        Text(duration.localizedTitle).tag(duration)
                    }
                }
            }

            Section(String(localized: "settings.section.feedback")) {
                Toggle(String(localized: "settings.toggle.sound-feedback"), isOn: $appState.soundFeedbackEnabled)
                    .accessibilityIdentifier("settings.toggle.sound-feedback")
                Toggle(String(localized: "settings.toggle.visual-feedback"), isOn: $appState.visualFeedbackEnabled)
                    .accessibilityIdentifier("settings.toggle.visual-feedback")
            }

            Section(String(localized: "settings.section.stats-today")) {
                LabeledContent(String(localized: "settings.label.auto-switches"), value: "\(stats.autoSwitchesToday)")
                LabeledContent(String(localized: "settings.label.manual-switches"), value: "\(stats.manualSwitchesToday)")
                LabeledContent(String(localized: "settings.label.words-committed"), value: "\(stats.wordsCommittedToday)")
                LabeledContent(String(localized: "settings.label.characters-saved"), value: "\(stats.charactersSavedToday)")
            }

            Section(String(localized: "settings.section.stats-alltime")) {
                LabeledContent(String(localized: "settings.label.auto-switches"), value: "\(stats.autoSwitchesTotal)")
                LabeledContent(String(localized: "settings.label.manual-switches"), value: "\(stats.manualSwitchesTotal)")
                LabeledContent(String(localized: "settings.label.words-committed"), value: "\(stats.wordsCommittedTotal)")
                LabeledContent(String(localized: "settings.label.characters-saved"), value: "\(stats.charactersSavedTotal)")
            }
        }
        .formStyle(.grouped)
    }
}

/// Static about pane shown in preferences.
private struct AboutTab: View {
    /// Displays app identity, short description, and diagnostic controls.
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 48))
            Text(String(localized: "settings.about.title"))
                .font(.title2).bold()
            Text(String(localized: "settings.about.description"))
                .foregroundStyle(.secondary)

            Button(action: exportLogs) {
                Label(String(localized: "settings.button.export-logs"), systemImage: "doc.text")
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    /// Opens a save panel to export recent os_log entries for bug reporting.
    private func exportLogs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = String(localized: "settings.logs.export-filename")
        let exporter = DiagnosticsLogExporter()
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await exporter.export(to: url)
            }
        }
    }
}
