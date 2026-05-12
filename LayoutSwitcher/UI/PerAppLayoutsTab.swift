import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings tab letting the user pin specific apps to a preferred keyboard layout.
/// On focus change the pipeline auto-selects the configured layout — preventing
/// typing-in-the-wrong-layout before auto-detection has to kick in.
struct PerAppLayoutsTab: View {
    @Bindable var preferences: PerAppLayoutPreferences
    @Bindable var inputSources: InputSourceManager
    @State private var selection: String?

    /// Renders the per-app layout list with inline layout picker per row.
    var body: some View {
        VStack(spacing: 12) {
            Text(String(localized: "settings.per-app-layouts.description"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            List(preferences.sortedEntries(), id: \.bundleID, selection: $selection) { entry in
                HStack(spacing: 12) {
                    Image(systemName: "keyboard.badge.ellipsis")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.appName)
                        Text(entry.bundleID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: layoutBinding(for: entry.bundleID)) {
                        ForEach(availableLayouts, id: \.id) { layout in
                            Text(layout.localizedName).tag(layout.id)
                        }
                        if !availableLayouts.contains(where: { $0.id == entry.layoutID }) {
                            Text(missingLabel(for: entry.layoutID)).tag(entry.layoutID)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
                .tag(entry.bundleID)
            }
            .frame(minHeight: 240)

            HStack {
                Button(action: addApp) {
                    Label(String(localized: "settings.per-app-layouts.add-app"), systemImage: "plus")
                }
                Button(action: removeSelected) {
                    Label(String(localized: "settings.per-app-layouts.remove"), systemImage: "minus")
                }
                .disabled(selection == nil)
                Spacer()
            }
        }
        .padding()
    }

    /// Layouts currently enabled in System Settings — eligible picker options.
    private var availableLayouts: [InputSource] {
        inputSources.enabledLayouts()
    }

    /// Two-way binding between a per-app entry and the preferences store.
    private func layoutBinding(for bundleID: String) -> Binding<String> {
        Binding(
            get: { preferences.preferredLayout(for: bundleID) ?? "" },
            set: { newValue in
                if !newValue.isEmpty {
                    preferences.set(layoutID: newValue, for: bundleID)
                }
            }
        )
    }

    /// Shown when a previously-configured layout was uninstalled from the system.
    private func missingLabel(for layoutID: String) -> String {
        String(format: String(localized: "settings.per-app-layouts.layout-missing"), layoutID)
    }

    /// Opens the app picker and saves the selected bundle with the current layout as default.
    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else {
            return
        }
        let initialLayout = inputSources.current?.id ?? availableLayouts.first?.id ?? ""
        if !initialLayout.isEmpty {
            preferences.set(layoutID: initialLayout, for: bundleID)
        }
    }

    /// Removes the selected app from the preferences list.
    private func removeSelected() {
        if let id = selection {
            preferences.remove(id)
            selection = nil
        }
    }
}
