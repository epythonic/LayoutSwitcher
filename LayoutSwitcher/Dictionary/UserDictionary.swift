import Foundation
import Observation
import os

@MainActor
@Observable
final class UserDictionary: WordDictionary {
    private static let logger = Logger(subsystem: "GM.LayoutSwitcher", category: "UserDictionary")

    let language: LanguageID
    private(set) var words: Set<String>

    private let storageURL: URL
    private let createDirectory: @MainActor (URL) throws -> Void
    private let fileExists: @MainActor (String) -> Bool
    private let readData: @MainActor (URL) throws -> Data
    private let writeData: @MainActor (Data, URL) throws -> Void

    /// Creates a user dictionary backed by the provided file manager.
    convenience init(
        language: LanguageID,
        storageURL: URL? = nil,
        fileManager: FileManager
    ) {
        let resolvedStorageURL = storageURL ?? Self.fileURL(for: language, fileManager: fileManager)
        self.init(
            language: language,
            storageURL: resolvedStorageURL,
            createDirectory: { url in
                try fileManager.createDirectory(
                    at: url,
                    withIntermediateDirectories: true
                )
            },
            fileExists: { path in
                fileManager.fileExists(atPath: path)
            },
            readData: { url in
                try Data(contentsOf: url)
            },
            writeData: { data, url in
                try data.write(to: url, options: .atomic)
            }
        )
    }

    /// Creates a user dictionary with injectable storage closures for deterministic tests.
    init(
        language: LanguageID,
        storageURL: URL,
        createDirectory: @escaping @MainActor (URL) throws -> Void,
        fileExists: @escaping @MainActor (String) -> Bool,
        readData: @escaping @MainActor (URL) throws -> Data,
        writeData: @escaping @MainActor (Data, URL) throws -> Void
    ) {
        self.language = language
        self.storageURL = storageURL
        self.createDirectory = createDirectory
        self.fileExists = fileExists
        self.readData = readData
        self.writeData = writeData
        self.words = Self.load(from: self.storageURL, fileExists: fileExists, readData: readData)
    }

    func contains(_ word: String) -> Bool {
        words.contains(InMemoryDictionary.normalize(word))
    }

    var size: Int { words.count }

    func add(_ word: String) {
        let normalized = InMemoryDictionary.normalize(word)
        guard !normalized.isEmpty else { return }
        words.insert(normalized)
        persist()
    }

    func remove(_ word: String) {
        let normalized = InMemoryDictionary.normalize(word)
        words.remove(normalized)
        persist()
    }

    func sortedWords() -> [String] {
        Array(words).sorted()
    }

    func importFromText(_ text: String) {
        let lines = text.split(whereSeparator: { $0.isNewline })
        for line in lines {
            let normalized = InMemoryDictionary.normalize(String(line))
            if !normalized.isEmpty {
                words.insert(normalized)
            }
        }
        persist()
    }

    private func persist() {
        do {
            try createDirectory(storageURL.deletingLastPathComponent())
            let payload = ["words": Array(words).sorted()]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            try writeData(data, storageURL)
        } catch {
            Self.logger.error("Failed to persist user dictionary \(self.language.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private static func load(
        from url: URL,
        fileExists: @MainActor (String) -> Bool,
        readData: @MainActor (URL) throws -> Data
    ) -> Set<String> {
        guard fileExists(url.path) else { return [] }
        do {
            let data = try readData(url)
            let payload = try JSONSerialization.jsonObject(with: data) as? [String: [String]]
            let raw = payload?["words"] ?? []
            return Set(raw.map { InMemoryDictionary.normalize($0) }.filter { !$0.isEmpty })
        } catch {
            Self.logger.error("Failed to load user dictionary at \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            return []
        }
    }

    private static func fileURL(for language: LanguageID, fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("LayoutSwitcher", isDirectory: true)
            .appendingPathComponent("user-dict-\(language.rawValue).json")
    }
}
