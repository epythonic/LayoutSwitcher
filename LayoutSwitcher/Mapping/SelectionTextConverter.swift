import Foundation
import os

/// Converts plain selected text between supported keyboard layouts.
@MainActor
struct SelectionTextConverter {
    nonisolated static let absoluteMaxSelectionLength = 20_000
    nonisolated static let defaultMaxSelectionLength = 5_000

    private let mapping: any KeyboardMapping
    private let maxSelectionLengthProvider: () -> Int

    init(mapping: any KeyboardMapping, maxSelectionLength: Int = Self.defaultMaxSelectionLength) {
        self.mapping = mapping
        self.maxSelectionLengthProvider = { maxSelectionLength }
    }

    init(mapping: any KeyboardMapping, maxSelectionLengthProvider: @escaping () -> Int) {
        self.mapping = mapping
        self.maxSelectionLengthProvider = maxSelectionLengthProvider
    }

    var maxSelectionLength: Int {
        Self.clampedMaxSelectionLength(maxSelectionLengthProvider())
    }

    static func clampedMaxSelectionLength(_ value: Int) -> Int {
        max(100, min(absoluteMaxSelectionLength, value))
    }

    /// Converts text using keyboard-mapping transposition.
    func convert(_ text: String) -> String {
        let trimmed = String(text.prefix(maxSelectionLength))
        let sourceLanguage = detectLanguage(trimmed)
        let targetLanguage = target(for: sourceLanguage)
        return mapping.convert(trimmed, from: sourceLanguage, to: targetLanguage)
    }

    private func detectLanguage(_ text: String) -> LanguageID {
        let cyrillicRange = "\u{0400}"..."\u{04FF}"
        return text.contains(where: { cyrillicRange.contains(String($0)) }) ? .ru : .en
    }

    private func target(for source: LanguageID) -> LanguageID {
        switch source {
        case .en: return .ru
        case .ru, .uk: return .en
        case .ro: return .en
        }
    }
}
