import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Language-specific user dictionary management tab.
struct DictionariesTab: View {
    /// User-maintained English dictionary.
    @Bindable var english: UserDictionary
    /// User-maintained Russian dictionary.
    @Bindable var russian: UserDictionary
    /// User-maintained Ukrainian dictionary.
    @Bindable var ukrainian: UserDictionary
    /// User-maintained Romanian dictionary.
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
    /// Dictionary model edited by this pane.
    @Bindable var dictionary: UserDictionary
    /// Text field contents before the word is committed.
    @State private var input: String = ""
    /// Currently selected word in the dictionary list.
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
