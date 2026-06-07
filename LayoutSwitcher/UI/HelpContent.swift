import Foundation
import os

/// Help content rendered by `HelpView`. Sections are ordered for first-time users,
/// daily workflows, advanced settings, and troubleshooting. Body text is loaded
/// lazily from bundled markdown files (`Help_<lang>.md`) so this Swift module
/// stays small and translators can edit prose as plain markdown.
struct HelpSection: Identifiable, Hashable, Sendable {
    /// Stable section identifier matching markdown `## <id>` headings.
    let id: String
    /// SF Symbol name reserved for section list or future richer navigation.
    let systemImage: String

    /// Localized section title shown in help navigation and detail panes.
    var localizedTitle: String {
        localizedString("help.section.\(id).title")
    }

    /// Localized short summary for compact help previews.
    var localizedSummary: String {
        localizedString("help.section.\(id).summary")
    }

    /// Localized markdown body for the user's preferred app language.
    var localizedBody: String {
        BundledHelpLoader.body(for: id, language: HelpSection.activeLanguage)
    }

    /// English body, primarily used by tests and fallback checks.
    var bodyEN: String { BundledHelpLoader.body(for: id, language: .en) }
    /// Russian body, primarily used by tests and fallback checks.
    var bodyRU: String { BundledHelpLoader.body(for: id, language: .ru) }
    /// Romanian body, primarily used by tests and fallback checks.
    var bodyRO: String { BundledHelpLoader.body(for: id, language: .ro) }
    /// Ukrainian body, primarily used by tests and fallback checks.
    var bodyUK: String { BundledHelpLoader.body(for: id, language: .uk) }

    /// Supported help markdown languages.
    enum HelpLanguage: String, CaseIterable, Sendable {
        /// English help content.
        case en
        /// Russian help content.
        case ru
        /// Romanian help content.
        case ro
        /// Ukrainian help content.
        case uk
    }

    /// Resolves a localized string table key.
    private func localizedString(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }

    /// Maps the current preferred locale to one bundled help language.
    fileprivate static var activeLanguage: HelpLanguage {
        let preferred = (Locale.preferredLanguages.first ?? "en").lowercased()
        if preferred.hasPrefix("ru") { return .ru }
        if preferred.hasPrefix("ro") { return .ro }
        if preferred.hasPrefix("uk") { return .uk }
        return .en
    }
}

/// Static ordered registry of help sections.
enum HelpContent {
    /// Sections shown by `HelpView` in sidebar order.
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
    /// Loads raw markdown for one help language.
    typealias ResourceLoader = @MainActor (HelpSection.HelpLanguage) -> String?

    /// Help loader diagnostics logger.
    private static let logger = Logger(subsystem: "GM.LayoutSwitcher", category: "Help")
    /// Injected markdown resource loader.
    private let resourceLoader: ResourceLoader
    /// Parsed bodies cached per language and section ID.
    private var cache: [HelpSection.HelpLanguage: [String: String]] = [:]

    /// Creates a loader backed by bundled markdown files from the provided bundle.
    init(bundle: Bundle = .main) {
        self.init(resourceLoader: { language in
            Self.bundledResource(for: language, bundle: bundle)
        })
    }

    /// Creates a loader with injectable markdown resources for deterministic tests.
    init(resourceLoader: @escaping ResourceLoader) {
        self.resourceLoader = resourceLoader
    }

    /// Returns one localized help body, falling back to English when needed.
    mutating func body(for id: String, language: HelpSection.HelpLanguage) -> String {
        let bodies = bodies(for: language)
        if let body = bodies[id] {
            return body
        }
        // Fall back to English so the panel never shows blank if a translation
        // is incomplete for one section.
        if language != .en {
            let englishBodies = self.bodies(for: .en)
            if let englishBody = englishBodies[id] {
                return englishBody
            }
        }
        Self.logMissingBody(for: id)
        return ""
    }

    /// Returns parsed bodies for one language, loading the markdown once per loader instance.
    mutating func bodies(for language: HelpSection.HelpLanguage) -> [String: String] {
        if let bodies = cache[language] {
            return bodies
        }
        let bodies = loadBodies(for: language)
        cache[language] = bodies
        return bodies
    }

    /// Loads and parses all section bodies for one language.
    private mutating func loadBodies(for language: HelpSection.HelpLanguage) -> [String: String] {
        guard let raw = resourceLoader(language) else {
            Self.logger.error("could not load Help_\(language.rawValue, privacy: .public).md from bundle")
            return [:]
        }
        return Self.parseSections(raw)
    }

    /// Reads one bundled `Help_<lang>.md` resource.
    private static func bundledResource(for language: HelpSection.HelpLanguage, bundle: Bundle) -> String? {
        let resource = "Help_\(language.rawValue)"
        guard let url = bundle.url(forResource: resource, withExtension: "md"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return raw
    }

    /// Logs a missing section body in production and test diagnostics.
    fileprivate static func logMissingBody(for id: String) {
        Self.logger.error("missing help body for section \"\(id, privacy: .public)\"")
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
    /// Immutable snapshot of bundled help bodies loaded lazily on first use.
    private static let bodiesByLanguage: [HelpSection.HelpLanguage: [String: String]] = {
        var loader = HelpBodyLoader()
        var result: [HelpSection.HelpLanguage: [String: String]] = [:]
        for language in HelpSection.HelpLanguage.allCases {
            result[language] = loader.bodies(for: language)
        }
        return result
    }()

    /// Returns one cached localized body for a section.
    fileprivate static func body(for id: String, language: HelpSection.HelpLanguage) -> String {
        if let body = bodiesByLanguage[language]?[id] {
            return body
        }
        if language != .en, let englishBody = bodiesByLanguage[.en]?[id] {
            return englishBody
        }
        HelpBodyLoader.logMissingBody(for: id)
        return ""
    }

    /// Exposes section parsing for deterministic tests.
    static func parseSections(_ markdown: String) -> [String: String] {
        HelpBodyLoader.parseSections(markdown)
    }
}
