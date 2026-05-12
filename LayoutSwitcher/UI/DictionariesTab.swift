import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Language-specific user dictionary management tab.
struct DictionariesTab: View {
    @Bindable var english: UserDictionary
    @Bindable var russian: UserDictionary
    @Bindable var ukrainian: UserDictionary
    @Bindable var romanian: UserDictionary

    /// Shows one editor per supported language.
    var body: some View {
        TabView {
            DictionaryEditor(dictionary: english)
                .tabItem { Text(english.language.localizedTitle) }
            DictionaryEditor(dictionary: russian)
                .tabItem { Text(russian.language.localizedTitle) }
            DictionaryEditor(dictionary: ukrainian)
                .tabItem { Text(ukrainian.language.localizedTitle) }
            DictionaryEditor(dictionary: romanian)
                .tabItem { Text(romanian.language.localizedTitle) }
        }
        .padding()
    }
}

/// Editor for a single language user dictionary.
private struct DictionaryEditor: View {
    @Bindable var dictionary: UserDictionary
    @State private var input: String = ""
    @State private var selection: String?

    /// Renders add/list/remove/import controls for a dictionary.
    var body: some View {
        VStack(spacing: 12) {
            Text(String(format: String(localized: "settings.dictionaries.description-format"), dictionary.language.localizedTitle))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                TextField(String(localized: "settings.dictionaries.add-word-placeholder"), text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addCurrent)
                Button(String(localized: "settings.dictionaries.add"), action: addCurrent)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            List(dictionary.sortedWords(), id: \.self, selection: $selection) { word in
                Text(word).tag(word)
            }
            .frame(minHeight: 180)

            HStack {
                Button(action: removeSelected) {
                    Label(String(localized: "settings.dictionaries.remove"), systemImage: "minus")
                }
                .disabled(selection == nil)
                Spacer()
                Button(String(localized: "settings.dictionaries.import-txt"), action: importFile)
                Text(String(format: String(localized: "settings.dictionaries.word-count-format"), dictionary.size))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Adds current input string to dictionary after trimming.
    private func addCurrent() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        dictionary.add(trimmed)
        input = ""
    }

    /// Removes currently selected word from dictionary.
    private func removeSelected() {
        if let word = selection {
            dictionary.remove(word)
            selection = nil
        }
    }

    /// Imports plain-text word list from chosen file.
    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK,
              let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        dictionary.importFromText(text)
    }
}
