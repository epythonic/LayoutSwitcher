import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings tab for managing app exclusions from automatic switching.
struct ExclusionsTab: View {
    /// Exclusion list model persisted through `UserDefaults`.
    @Bindable var exclusions: ExclusionList
    /// Currently selected bundle identifier in the exclusions list.
    @State private var selection: String?

    /// Renders exclusion list and add/remove/reset controls.
    var body: some View {
        VStack(spacing: 12) {
            Text(String(localized: "settings.exclusions.description"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            List(exclusions.sortedEntries(), id: \.bundleID, selection: $selection) { entry in
                HStack {
                    Image(systemName: "app.dashed")
                        .accessibilityHidden(true)
                    VStack(alignment: .leading) {
                        Text(entry.name)
                        Text(entry.bundleID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(entry.bundleID)
            }
            .frame(minHeight: 220)

            HStack {
                Button(action: addApp) {
                    Label(String(localized: "settings.exclusions.add-app"), systemImage: "plus")
                }
                Button(action: removeSelected) {
                    Label(String(localized: "settings.exclusions.remove"), systemImage: "minus")
                }
                .disabled(selection == nil)
                Spacer()
                Button(String(localized: "settings.exclusions.reset-defaults"), role: .destructive, action: resetDefaults)
            }
        }
        .padding()
    }

    /// Opens app picker and adds selected app bundle to exclusions.
    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let bundleID = Bundle(url: url)?.bundleIdentifier {
            exclusions.add(bundleID)
        }
    }

    /// Removes selected bundle identifier from exclusions.
    private func removeSelected() {
        if let id = selection {
            exclusions.remove(id)
            selection = nil
        }
    }

    /// Restores exclusions list to default baseline set.
    private func resetDefaults() {
        for id in Array(exclusions.bundleIDs) where !ExclusionList.defaults.contains(id) {
            exclusions.remove(id)
        }
        for id in ExclusionList.defaults {
            exclusions.add(id)
        }
    }
}
