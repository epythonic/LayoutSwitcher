import Foundation
import Observation
import os

@MainActor
@Observable
final class UserDictionary: WordDictionary {
    private static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "UserDictionary")

    let language: LanguageID
    private(set) var words: Set<String>

    private let storageURL: URL

    init(language: LanguageID, storageURL: URL? = nil) {
        self.language = language
        self.storageURL = storageURL ?? Self.fileURL(for: language)
        self.words = Self.load(from: self.storageURL)
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
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let payload = ["words": Array(words).sorted()]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            try data.write(to: storageURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to persist user dictionary \(self.language.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private static func load(from url: URL) -> Set<String> {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONSerialization.jsonObject(with: data) as? [String: [String]]
            let raw = payload?["words"] ?? []
            return Set(raw.map { InMemoryDictionary.normalize($0) }.filter { !$0.isEmpty })
        } catch {
            logger.error("Failed to load user dictionary at \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            return []
        }
    }

    private static func fileURL(for language: LanguageID) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("LayoutSwitcher", isDirectory: true)
            .appendingPathComponent("user-dict-\(language.rawValue).json")
    }
}
