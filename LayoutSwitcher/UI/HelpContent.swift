import Foundation
import os

/// Help content rendered by `HelpView`. Sections are ordered for first-time users,
/// daily workflows, advanced settings, and troubleshooting. Body text is loaded
/// lazily from bundled markdown files (`Help_<lang>.md`) so this Swift module
/// stays small and translators can edit prose as plain markdown.
struct HelpSection: Identifiable, Hashable {
    let id: String
    let systemImage: String
    let titleEN: String
    let titleRU: String
    let titleRO: String
    let titleUK: String
    let summaryEN: String
    let summaryRU: String
    let summaryRO: String
    let summaryUK: String

    var localizedTitle: String {
        switch HelpSection.activeLanguage {
        case .ru: return titleRU
        case .ro: return titleRO
        case .uk: return titleUK
        case .en: return titleEN
        }
    }

    var localizedSummary: String {
        switch HelpSection.activeLanguage {
        case .ru: return summaryRU
        case .ro: return summaryRO
        case .uk: return summaryUK
        case .en: return summaryEN
        }
    }

    var localizedBody: String {
        BundledHelpLoader.body(for: id, language: HelpSection.activeLanguage)
    }

    var bodyEN: String { BundledHelpLoader.body(for: id, language: .en) }
    var bodyRU: String { BundledHelpLoader.body(for: id, language: .ru) }
    var bodyRO: String { BundledHelpLoader.body(for: id, language: .ro) }
    var bodyUK: String { BundledHelpLoader.body(for: id, language: .uk) }

    fileprivate enum HelpLanguage: String { case en, ru, ro, uk }

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
        HelpSection(
            id: "overview",
            systemImage: "keyboard",
            titleEN: "What LayoutSwitcher Does",
            titleRU: "Что делает LayoutSwitcher",
            titleRO: "Ce face LayoutSwitcher",
            titleUK: "Що робить LayoutSwitcher",
            summaryEN: "The app fixes words typed in the wrong keyboard layout.",
            summaryRU: "Приложение исправляет слова, набранные не в той раскладке.",
            summaryRO: "Aplicația repară cuvintele tastate în aranjamentul greșit.",
            summaryUK: "Застосунок виправляє слова, набрані не в тій розкладці."
        ),
        HelpSection(
            id: "first-setup",
            systemImage: "checklist",
            titleEN: "First Setup",
            titleRU: "Первичная настройка",
            titleRO: "Configurare inițială",
            titleUK: "Початкове налаштування",
            summaryEN: "Accessibility permission and macOS input sources.",
            summaryRU: "Разрешение Accessibility и источники ввода macOS.",
            summaryRO: "Permisiune Accesibilitate și surse de intrare macOS.",
            summaryUK: "Дозвіл Accessibility та джерела вводу macOS."
        ),
        HelpSection(
            id: "automatic-correction",
            systemImage: "arrow.triangle.2.circlepath",
            titleEN: "Automatic Correction Flow",
            titleRU: "Флоу автоисправления",
            titleRO: "Flux de corecție automată",
            titleUK: "Флоу автовиправлення",
            summaryEN: "What happens after each word boundary.",
            summaryRU: "Что происходит после границы слова.",
            summaryRO: "Ce se întâmplă după fiecare graniță de cuvânt.",
            summaryUK: "Що відбувається після межі слова."
        ),
        HelpSection(
            id: "manual-actions",
            systemImage: "command",
            titleEN: "Manual Actions and Hotkeys",
            titleRU: "Ручные действия и хоткеи",
            titleRO: "Acțiuni manuale și scurtături",
            titleUK: "Ручні дії та хоткеї",
            summaryEN: "Manual toggle, undo, and selection conversion.",
            summaryRU: "Ручное переключение, отмена и конвертация выделения.",
            summaryRO: "Comutare manuală, anulare și conversia selecției.",
            summaryUK: "Ручне перемикання, скасування та конвертація виділення."
        ),
        HelpSection(
            id: "selection-conversion",
            systemImage: "selection.pin.in.out",
            titleEN: "Convert Selected Text",
            titleRU: "Конвертация выделенного текста",
            titleRO: "Conversia textului selectat",
            titleUK: "Конвертація виділеного тексту",
            summaryEN: "The safe way to fix whole sentences or paragraphs.",
            summaryRU: "Безопасный способ чинить предложения и абзацы.",
            summaryRO: "Modul sigur de a repara propoziții sau paragrafe întregi.",
            summaryUK: "Безпечний спосіб виправляти речення та абзаци."
        ),
        HelpSection(
            id: "preferences",
            systemImage: "slider.horizontal.3",
            titleEN: "Preferences and Parameters",
            titleRU: "Настройки и параметры",
            titleRO: "Preferințe și parametri",
            titleUK: "Налаштування та параметри",
            summaryEN: "What each Preferences tab controls.",
            summaryRU: "За что отвечает каждая вкладка настроек.",
            summaryRO: "Ce controlează fiecare tab din setări.",
            summaryUK: "За що відповідає кожна вкладка налаштувань."
        ),
        HelpSection(
            id: "languages",
            systemImage: "globe",
            titleEN: "Languages and Layouts",
            titleRU: "Языки и раскладки",
            titleRO: "Limbi și aranjamente",
            titleUK: "Мови та розкладки",
            summaryEN: "How EN, RU, UA, and RO are detected.",
            summaryRU: "Как определяются EN, RU, UA и RO.",
            summaryRO: "Cum sunt detectate EN, RU, UA și RO.",
            summaryUK: "Як визначаються EN, RU, UA та RO."
        ),
        HelpSection(
            id: "romanian-diacritics",
            systemImage: "textformat.abc.dottedunderline",
            titleEN: "Romanian Diacritics",
            titleRU: "Румынские диакритики",
            titleRO: "Diacritice românești",
            titleUK: "Румунські діакритики",
            summaryEN: "Optional ASCII-to-diacritics correction for Romanian.",
            summaryRU: "Опциональная замена ASCII на диакритики для RO.",
            summaryRO: "Corecție opțională ASCII → diacritice pentru română.",
            summaryUK: "Опціональна заміна ASCII на діакритики для RO."
        ),
        HelpSection(
            id: "user-dictionaries",
            systemImage: "character.book.closed",
            titleEN: "User Dictionaries",
            titleRU: "Пользовательские словари",
            titleRO: "Dicționare utilizator",
            titleUK: "Користувацькі словники",
            summaryEN: "Teach the detector your names, brands, and jargon.",
            summaryRU: "Имена, бренды и терминология для детектора.",
            summaryRO: "Învață detectorul numele, brandurile și jargonul tău.",
            summaryUK: "Імена, бренди та термінологія для детектора."
        ),
        HelpSection(
            id: "exclusions",
            systemImage: "nosign",
            titleEN: "App Exclusions",
            titleRU: "Исключения приложений",
            titleRO: "Excluderi de aplicații",
            titleUK: "Винятки застосунків",
            summaryEN: "Disable automatic retyping in sensitive apps.",
            summaryRU: "Отключение автоперепечати в чувствительных приложениях.",
            summaryRO: "Dezactivează retastarea automată în aplicații sensibile.",
            summaryUK: "Вимкнення автоперенабору в чутливих застосунках."
        ),
        HelpSection(
            id: "privacy",
            systemImage: "lock.shield",
            titleEN: "Privacy and Safety",
            titleRU: "Приватность и безопасность",
            titleRO: "Confidențialitate și siguranță",
            titleUK: "Приватність та безпека",
            summaryEN: "What is stored, skipped, and never sent.",
            summaryRU: "Что хранится, пропускается и не отправляется.",
            summaryRO: "Ce se stochează, ce se sare și ce nu se trimite niciodată.",
            summaryUK: "Що зберігається, пропускається і не надсилається."
        ),
        HelpSection(
            id: "troubleshooting",
            systemImage: "wrench.and.screwdriver",
            titleEN: "Troubleshooting",
            titleRU: "Диагностика",
            titleRO: "Depanare",
            titleUK: "Діагностика",
            summaryEN: "Checks for common failure modes.",
            summaryRU: "Проверки для частых проблем.",
            summaryRO: "Verificări pentru moduri de eșec comune.",
            summaryUK: "Перевірки для типових проблем."
        )
    ]
}

/// Loads bundled help bodies from `Help_<lang>.md`. Each markdown file uses
/// `## <section-id>` H2 headings as section delimiters. Files are read once
/// and cached for subsequent lookups.
enum BundledHelpLoader {
    private static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "Help")
    private static var cache: [HelpSection.HelpLanguage: [String: String]] = [:]

    fileprivate static func body(for id: String, language: HelpSection.HelpLanguage) -> String {
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
        logger.error("missing help body for section \"\(id, privacy: .public)\"")
        return ""
    }

    private static func loadBodies(for language: HelpSection.HelpLanguage) -> [String: String] {
        let resource = "Help_\(language.rawValue)"
        guard let url = Bundle.main.url(forResource: resource, withExtension: "md"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            logger.error("could not load \(resource, privacy: .public).md from bundle")
            return [:]
        }
        return parseSections(raw)
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
