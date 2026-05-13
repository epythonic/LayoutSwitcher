import Foundation
import os

/// Help content rendered by `HelpView`. Sections are ordered for first-time users,
/// daily workflows, advanced settings, and troubleshooting. Body text is loaded
/// lazily from bundled markdown files (`Help_<lang>.md`) so this Swift module
/// stays small and translators can edit prose as plain markdown.
struct HelpSection: Identifiable, Hashable, Sendable {
    let id: String
    let systemImage: String

    var localizedTitle: String {
        localizedString("help.section.\(id).title")
    }

    var localizedSummary: String {
        localizedString("help.section.\(id).summary")
    }

    var localizedBody: String {
        BundledHelpLoader.body(for: id, language: HelpSection.activeLanguage)
    }

    var bodyEN: String { BundledHelpLoader.body(for: id, language: .en) }
    var bodyRU: String { BundledHelpLoader.body(for: id, language: .ru) }
    var bodyRO: String { BundledHelpLoader.body(for: id, language: .ro) }
    var bodyUK: String { BundledHelpLoader.body(for: id, language: .uk) }

    enum HelpLanguage: String, Sendable { case en, ru, ro, uk }

    private func localizedString(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }

    fileprivate static var activeLanguage: HelpLanguage {
        let preferred = (Locale.preferredLanguages.first ?? "en").lowercased()
        if preferred.hasPrefix("ru") { return .ru }
        if preferred.hasPrefix("ro") { return .ro }
        if preferred.hasPrefix("uk") { return .uk }
        return .en
    }
}

enum HelpContent {
    static let sections: [HelpSection] = [
        HelpSection(id: "overview", systemImage: "keyboard"),
        HelpSection(id: "first-setup", systemImage: "checklist"),
        HelpSection(id: "automatic-correction", systemImage: "arrow.triangle.2.circlepath"),
        HelpSection(id: "extending-corrections", systemImage: "arrow.left.and.line.vertical.and.arrow.right"),
        HelpSection(id: "manual-actions", systemImage: "command"),
        HelpSection(id: "selection-conversion", systemImage: "selection.pin.in.out"),
        HelpSection(id: "preferences", systemImage: "slider.horizontal.3"),
        HelpSection(id: "languages", systemImage: "globe"),
        HelpSection(id: "romanian-diacritics", systemImage: "textformat.abc.dottedunderline"),
        HelpSection(id: "user-dictionaries", systemImage: "character.book.closed"),
        HelpSection(id: "exclusions", systemImage: "nosign"),
        HelpSection(id: "privacy", systemImage: "lock.shield"),
        HelpSection(id: "troubleshooting", systemImage: "wrench.and.screwdriver")
    ]
}

/// Stateful loader for help bodies with injectable markdown resources.
@MainActor
struct HelpBodyLoader {
    typealias ResourceLoader = @MainActor (HelpSection.HelpLanguage) -> String?

    private static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "Help")
    private let resourceLoader: ResourceLoader
    private var cache: [HelpSection.HelpLanguage: [String: String]] = [:]

    /// Creates a loader backed by bundled markdown files unless a test loader is supplied.
    init(resourceLoader: @escaping ResourceLoader = Self.bundledResource(for:)) {
        self.resourceLoader = resourceLoader
    }

    /// Returns one localized help body, falling back to English when needed.
    mutating func body(for id: String, language: HelpSection.HelpLanguage) -> String {
        if let bodies = cache[language], let body = bodies[id] {
            return body
        }
        let bodies = loadBodies(for: language)
        cache[language] = bodies
        if let body = bodies[id] {
            return body
        }
        // Fall back to English so the panel never shows blank if a translation
        // is incomplete for one section.
        if language != .en {
            return body(for: id, language: .en)
        }
        Self.logger.error("missing help body for section \"\(id, privacy: .public)\"")
        return ""
    }

    private mutating func loadBodies(for language: HelpSection.HelpLanguage) -> [String: String] {
        guard let raw = resourceLoader(language) else {
            Self.logger.error("could not load Help_\(language.rawValue, privacy: .public).md from bundle")
            return [:]
        }
        return Self.parseSections(raw)
    }

    private static func bundledResource(for language: HelpSection.HelpLanguage) -> String? {
        let resource = "Help_\(language.rawValue)"
        guard let url = Bundle.main.url(forResource: resource, withExtension: "md"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return raw
    }

    /// Splits a help markdown file by `## <id>` headings. Body text is
    /// trimmed but otherwise preserved verbatim (including bullets, arrows,
    /// inline emphasis).
    static func parseSections(_ markdown: String) -> [String: String] {
        var sections: [String: String] = [:]
        var currentID: String?
        var buffer: [String] = []

        func flush() {
            guard let id = currentID else { return }
            let body = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            sections[id] = body
        }

        for line in markdown.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                flush()
                currentID = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                buffer.removeAll(keepingCapacity: true)
            } else {
                buffer.append(line)
            }
        }
        flush()
        return sections
    }
}

/// Loads bundled help bodies from `Help_<lang>.md`. Each markdown file uses
/// `## <section-id>` H2 headings as section delimiters. Files are read once
/// and cached for subsequent lookups.
enum BundledHelpLoader {
    private static var shared = HelpBodyLoader()

    fileprivate static func body(for id: String, language: HelpSection.HelpLanguage) -> String {
        shared.body(for: id, language: language)
    }

    static func parseSections(_ markdown: String) -> [String: String] {
        HelpBodyLoader.parseSections(markdown)
    }
}
