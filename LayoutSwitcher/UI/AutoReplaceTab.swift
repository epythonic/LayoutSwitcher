import SwiftUI

/// Settings tab for managing text auto-replace rules (trigger → replacement).
struct AutoReplaceTab: View {
    /// Auto-replace rule store persisted through `UserDefaults`.
    @Bindable var rules: AutoReplaceRules
    @State private var newTrigger: String = ""
    @State private var newReplacement: String = ""
    @State private var selection: String?

    /// Renders the inline toggle, the rules list, and add/remove controls.
    var body: some View {
        VStack(spacing: 12) {
            Text(String(localized: "settings.autoreplace.description"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(String(localized: "settings.autoreplace.inline-enabled"), isOn: $rules.isInlineEnabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            List(rules.rules, id: \.trigger, selection: $selection) { rule in
                HStack {
                    Text(rule.trigger).font(.body.monospaced())
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(rule.replacement).foregroundStyle(.secondary)
                }
                .tag(rule.trigger)
            }
            .frame(minHeight: 200)

            HStack {
                TextField(String(localized: "settings.autoreplace.trigger-placeholder"), text: $newTrigger)
                    .frame(maxWidth: 160)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(String(localized: "settings.autoreplace.replacement-placeholder"), text: $newReplacement)
                Button(action: addRule) {
                    Label(String(localized: "settings.autoreplace.add"), systemImage: "plus")
                }
                .disabled(newTrigger.trimmingCharacters(in: .whitespaces).isEmpty || newReplacement.isEmpty)
                Button(action: removeSelected) {
                    Label(String(localized: "settings.autoreplace.remove"), systemImage: "minus")
                }
                .disabled(selection == nil)
            }
        }
        .padding()
    }

    private func addRule() {
        rules.upsert(trigger: newTrigger, replacement: newReplacement)
        newTrigger = ""
        newReplacement = ""
    }

    private func removeSelected() {
        if let trigger = selection {
            rules.remove(trigger: trigger)
            selection = nil
        }
    }
}
