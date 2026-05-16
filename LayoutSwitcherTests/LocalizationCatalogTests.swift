import Foundation
import Testing

struct LocalizationCatalogTests {
    private typealias FileEnumerator = (
        _ root: URL,
        _ keys: [URLResourceKey]?,
        _ options: FileManager.DirectoryEnumerationOptions
    ) -> FileManager.DirectoryEnumerator?

    private static let supportedLanguages = ["en", "ru", "ro", "uk"]

    private static let hotkeyLocalizationKeys = [
        "settings.hotkeys.convert-last-sentence.subtitle",
        "settings.hotkeys.convert-last-sentence.title",
        "settings.hotkeys.convert-selection.subtitle",
        "settings.hotkeys.convert-selection.title",
        "settings.hotkeys.force-retype-last-word.subtitle",
        "settings.hotkeys.force-retype-last-word.title",
        "settings.hotkeys.manual-toggle.subtitle",
        "settings.hotkeys.manual-toggle.title",
        "settings.hotkeys.smart-paste.subtitle",
        "settings.hotkeys.smart-paste.title",
        "settings.hotkeys.snooze.subtitle",
        "settings.hotkeys.snooze.title",
        "settings.hotkeys.undo-auto-switch.subtitle",
        "settings.hotkeys.undo-auto-switch.title"
    ]

    private static let dynamicallyReferencedKeyPrefixes = [
        "help.section."
    ]

    @Test func hotkeyActionKeysAreTranslatedForSupportedLanguages() throws {
        let catalog = try Self.loadCatalog(named: "Localizable.xcstrings")

        for key in Self.hotkeyLocalizationKeys {
            let entry = try #require(catalog.strings[key])

            for language in Self.supportedLanguages {
                let unit = entry.localizations?[language]?.stringUnit
                let value = unit?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                #expect(unit?.state == "translated")
                #expect(!value.isEmpty)
                #expect(value != key)
            }
        }
    }

    @Test func infoPlistKeysAreTranslatedForSupportedLanguages() throws {
        let catalog = try Self.loadCatalog(named: "InfoPlist.xcstrings")

        for (key, entry) in catalog.strings {
            #expect(!key.isEmpty)

            for language in Self.supportedLanguages {
                let unit = entry.localizations?[language]?.stringUnit
                let value = unit?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                #expect(unit?.state == "translated")
                #expect(!value.isEmpty)
            }
        }
    }

    @Test func localizableKeysAreReferencedByApplicationSources() throws {
        let catalog = try Self.loadCatalog(named: "Localizable.xcstrings")
        let sourceText = try Self.applicationSourceText()

        for key in catalog.strings.keys.sorted() {
            let isReferenced = sourceText.contains("\"\(key)\"")
                || Self.isDynamicallyReferencedLocalizableKey(key)
            #expect(isReferenced, "Unused localization key: \(key)")
        }
    }

    @Test func applicationLocalizedStringKeysExistInCatalog() throws {
        let catalog = try Self.loadCatalog(named: "Localizable.xcstrings")
        let sourceText = try Self.applicationSourceText()
        let referencedKeys = Self.localizedStringKeys(in: sourceText)

        for key in referencedKeys.sorted() {
            #expect(catalog.strings[key] != nil, "Missing localization key referenced from Swift: \(key)")
        }
    }

    private static func loadCatalog(named fileName: String) throws -> StringCatalog {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL.deletingLastPathComponent().deletingLastPathComponent()
        let catalogURL = projectRoot.appending(path: "LayoutSwitcher/\(fileName)")
        let data = try Data(contentsOf: catalogURL)
        return try JSONDecoder().decode(StringCatalog.self, from: data)
    }

    private static func applicationSourceText() throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL.deletingLastPathComponent().deletingLastPathComponent()
        let sourceRoot = projectRoot.appending(path: "LayoutSwitcher")
        return try Self.swiftFiles(in: sourceRoot, enumerateFiles: Self.enumerateFiles)
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }

    private static func swiftFiles(
        in root: URL,
        enumerateFiles: FileEnumerator
    ) throws -> [URL] {
        guard let enumerator = enumerateFiles(
            root,
            [.isRegularFileKey],
            [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift" else {
                continue
            }

            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                files.append(fileURL)
            }
        }
        return files
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

    private static func localizedStringKeys(in sourceText: String) -> Set<String> {
        let marker = "String(localized:"
        var keys: Set<String> = []
        var searchRange = sourceText.startIndex..<sourceText.endIndex

        while let markerRange = sourceText.range(of: marker, range: searchRange) {
            let argumentStart = markerRange.upperBound
            var index = argumentStart
            var depth = 1
            var isInString = false
            var isEscaped = false

            while index < sourceText.endIndex {
                let character = sourceText[index]

                if isInString {
                    if isEscaped {
                        isEscaped = false
                    } else if character == "\\" {
                        isEscaped = true
                    } else if character == "\"" {
                        isInString = false
                    }
                } else {
                    if character == "\"" {
                        isInString = true
                    } else if character == "(" {
                        depth += 1
                    } else if character == ")" {
                        depth -= 1
                        if depth == 0 {
                            break
                        }
                    }
                }

                index = sourceText.index(after: index)
            }

            let argumentText = String(sourceText[argumentStart..<index])
            keys.formUnion(Self.stringLiterals(in: argumentText))

            if index < sourceText.endIndex {
                searchRange = sourceText.index(after: index)..<sourceText.endIndex
            } else {
                searchRange = sourceText.endIndex..<sourceText.endIndex
            }
        }

        return keys
    }

    private static func stringLiterals(in text: String) -> Set<String> {
        var literals: Set<String> = []
        var current = ""
        var isInString = false
        var isEscaped = false

        for character in text {
            if isInString {
                if isEscaped {
                    current.append(character)
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    literals.insert(current)
                    current = ""
                    isInString = false
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                isInString = true
            }
        }

        return literals
    }

    private static func isDynamicallyReferencedLocalizableKey(_ key: String) -> Bool {
        Self.dynamicallyReferencedKeyPrefixes.contains { key.hasPrefix($0) }
    }
}

private struct StringCatalog: Decodable {
    let strings: [String: StringCatalogEntry]
}

private struct StringCatalogEntry: Decodable {
    let localizations: [String: StringLocalization]?
}

private struct StringLocalization: Decodable {
    let stringUnit: StringUnit?
}

private struct StringUnit: Decodable {
    let state: String
    let value: String
}
