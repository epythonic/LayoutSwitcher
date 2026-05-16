import SwiftUI

/// Configurable hotkey bindings presentation tab.
struct HotkeysTab: View {
    /// Registry that stores current hotkey bindings and persists updates.
    @Bindable var registry: HotkeyRegistry
    /// Action currently being edited by the key recorder.
    @State private var editingAction: HotkeyAction?
    /// Whether the hidden recorder view should consume the next keydown.
    @State private var isRecording = false
    /// Action displaced by a newly chosen shortcut, if a conflict occurred.
    @State private var conflictedAction: HotkeyAction?
    /// Controls presentation of the binding-conflict alert.
    @State private var isConflictAlertPresented = false

    /// Renders currently configured hotkeys and their semantics.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "settings.hotkeys.title"))
                .font(.headline)
            Text(String(localized: "settings.hotkeys.description"))
                .font(.callout)
                .foregroundStyle(.secondary)

            ForEach(rows, id: \.action) { row in
                let editingThis = editingAction == row.action && isRecording
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).bold()
                        Text(row.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if editingThis {
                        Text(String(localized: "settings.hotkeys.recording"))
                            .font(.body.monospaced())
                            .foregroundStyle(.orange)
                    } else {
                        Text(row.shortcut)
                            .font(.body.monospaced())
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }

                    Button(action: {
                        if editingThis {
                            cancelEditing()
                        } else {
                            beginEditing(row.action)
                        }
                    }) {
                        if editingThis {
                            Text(String(localized: "settings.hotkeys.cancel"))
                        } else {
                            Text(String(localized: "settings.hotkeys.change"))
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRecording && !editingThis)
                }
                .padding(.vertical, 4)
                Divider()
            }

            Spacer()

            KeyRecorderView(isRecording: $isRecording, onCommit: handleCommit)
                .frame(width: 0, height: 0)
        }
        .padding()
        .alert(
            String(localized: "settings.hotkeys.conflict.title"),
            isPresented: $isConflictAlertPresented,
            presenting: conflictedAction
        ) { _ in
            Button(String(localized: "settings.hotkeys.conflict.ok")) { }
        } message: { action in
            Text(String(format: String(localized: "settings.hotkeys.conflict.message"), actionTitle(action)))
        }
    }

    /// View-model rows derived from current registry bindings.
    private var rows: [Row] {
        HotkeyAction.ordered.map { action in
            Row(
                action: action,
                title: action.localizedTitle,
                subtitle: action.localizedSubtitle,
                shortcut: shortcut(for: action)
            )
        }
    }

    /// Formats one action binding into human-readable keyboard shortcut string.
    private func shortcut(for action: HotkeyAction) -> String {
        guard let definition = registry.binding(for: action) else { return "—" }
        return definition.displayText
    }

    /// One rendered row in hotkeys list.
    private struct Row {
        /// Hotkey action represented by this row.
        let action: HotkeyAction
        /// Localized primary label.
        let title: String
        /// Localized explanatory subtitle.
        let subtitle: String
        /// Formatted shortcut text or dash when unbound.
        let shortcut: String
    }

    /// Starts key capture for a given hotkey action.
    private func beginEditing(_ action: HotkeyAction) {
        editingAction = action
        isRecording = true
    }

    /// Cancels key capture and returns to normal row view.
    private func cancelEditing() {
        editingAction = nil
        isRecording = false
    }

    /// Commits captured hotkey and updates the binding map.
    private func handleCommit(_ definition: HotkeyDefinition?) {
        if let definition, let action = editingAction {
            if let replacedAction = registry.setBinding(definition, action: action), replacedAction != action {
                conflictedAction = replacedAction
                isConflictAlertPresented = true
            }
        }
        cancelEditing()
    }

    /// Localized title for an action whose binding was replaced.
    private func actionTitle(_ action: HotkeyAction) -> String {
        action.localizedTitle
    }
}
