import SwiftUI
import UniformTypeIdentifiers
import os

/// Root preferences view grouping all settings tabs.
struct SettingsView: View {
    @Bindable var appState: AppState
    @Bindable var exclusions: ExclusionList
    @Bindable var stats: UsageStats
    @Bindable var userEnglish: UserDictionary
    @Bindable var userRussian: UserDictionary
    @Bindable var userUkrainian: UserDictionary
    @Bindable var userRomanian: UserDictionary
    @Bindable var inputSources: InputSourceManager
    @Bindable var hotkeys: HotkeyRegistry
    @Bindable var perAppLayouts: PerAppLayoutPreferences
    @Bindable var recents: RecentSwitches
    let learningCache: LearningCache
    let launchAtLoginManager: LaunchAtLoginManager

    /// Renders tabbed settings UI.
    var body: some View {
        TabView {
            GeneralTab(appState: appState, stats: stats, launchAtLoginManager: launchAtLoginManager)
                .tabItem { Label(String(localized: "settings.tab.general"), systemImage: "gearshape") }

            LayoutsTab(inputSources: inputSources)
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
        // Height accommodates the tallest tab — Dictionaries — which now includes the system
        // dictionary status header above the per-language editor. Smaller heights would clip
        // the editor's footer (entry counter + import button).
        .frame(width: 600, height: 700)
    }
}

/// General settings tab containing status, detector toggles, and statistics.
private struct GeneralTab: View {
    @Bindable var appState: AppState
    @Bindable var stats: UsageStats
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
                Toggle(String(localized: "settings.toggle.correct-single-char"), isOn: $appState.correctSingleCharacterWords)
                Toggle(String(localized: "settings.toggle.auto-extend-recent"), isOn: $appState.autoExtendRecentAmbiguous)
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
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            task.arguments = [
                "show",
                "--predicate", "subsystem == 'GIH.LayoutSwitcher'",
                "--info",
                "--last", "1h"
            ]
            let output = Pipe()
            task.standardOutput = output
            do {
                try task.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                try data.write(to: url)
            } catch {
                Logger(subsystem: "GIH.LayoutSwitcher", category: "ExportLogs").error("Export logs failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
