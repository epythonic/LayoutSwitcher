import CoreGraphics

/// Converts buffered keycodes to textual representations across supported languages.
protocol KeyboardMapping {
    /// Canonical pair this mapping primarily targets.
    var languagePair: LanguagePair { get }
    /// Alias for `render` used in pipeline naming context.
    func transliterate(_ chars: [WordChar], to language: LanguageID) -> String
    /// Renders a keycode buffer as if it were typed in given language layout.
    func render(_ chars: [WordChar], in language: LanguageID) -> String
    /// Finds keycode/shift pair for emitting a specific character in target language.
    func keyCode(for character: Character, language: LanguageID) -> (keyCode: CGKeyCode, shift: Bool)?
    /// Converts already-rendered text from one layout language to another layout language.
    func convert(_ text: String, from sourceLanguage: LanguageID, to targetLanguage: LanguageID) -> String

    /// Keycodes that render as punctuation in at least one supported layout but as
    /// letters in another. Tokenization uses this to avoid splitting words mid-token.
    var ambiguousWordInternalKeyCodes: Set<CGKeyCode> { get }

    /// Union of all characters produced by ambiguous keycodes across supported layouts.
    var ambiguousWordInternalCharacters: Set<Character> { get }
}

extension KeyboardMapping {
    /// Default empty sets for mappings that do not yet provide introspection.
    var ambiguousWordInternalKeyCodes: Set<CGKeyCode> { [] }
    var ambiguousWordInternalCharacters: Set<Character> { [] }
}

/// Static table-based mapping for RU/UK/EN QWERTY-compatible keyboard layouts.
struct RuEnQwertyMapping: KeyboardMapping {
    let languagePair: LanguagePair = .ruEn

    /// Stateless transliteration entry point.
    func transliterate(_ chars: [WordChar], to language: LanguageID) -> String {
        render(chars, in: language)
    }

    /// Romanian Standard layout shares letter keyCodes with US QWERTY for a–z.
    /// We render `.ro` using the English mapping so transliteration treats them identically.
    private static func resolvedLanguage(_ language: LanguageID) -> LanguageID {
        language == .ro ? .en : language
    }

    /// Reverse-maps character into keycode + shift combination for target layout.
    func keyCode(for character: Character, language: LanguageID) -> (keyCode: CGKeyCode, shift: Bool)? {
        let lower = Character(character.lowercased())
        let shift = (character != lower)
        let table = Self.table
        let resolved = Self.resolvedLanguage(language)
        for (code, entry) in table {
            let candidate: Character
            switch resolved {
            case .en: candidate = entry.en
            case .ru: candidate = entry.ru
            case .uk: candidate = Self.ukCharacter(for: code, fallback: entry.ru)
            default: continue
            }
            if candidate == lower {
                return (code, shift)
            }
        }
        return nil
    }

    /// Converts selected plain text by interpreting each convertible character as a key
    /// from the source layout, then rendering that key in the target layout.
    func convert(_ text: String, from sourceLanguage: LanguageID, to targetLanguage: LanguageID) -> String {
        let characters = Array(text)
        var result = ""
        result.reserveCapacity(characters.count)

        for index in characters.indices {
            let character = characters[index]
            guard shouldConvert(character, at: index, in: characters, sourceLanguage: sourceLanguage),
                  let key = keyCode(for: character, language: sourceLanguage) else {
                result.append(character)
                continue
            }
            var flags: CGEventFlags = []
            if key.shift {
                flags.insert(.maskShift)
            }
            let wordChar = WordChar(keyCode: key.keyCode, unicode: "", flags: flags, timestamp: 0)
            let converted = render([wordChar], in: targetLanguage)
            result.append(converted.isEmpty ? String(character) : converted)
        }
        return result
    }

    /// Avoids turning normal sentence punctuation into Cyrillic letters at word boundaries
    /// while still allowing punctuation-shaped keys inside wrong-layout words.
    private func shouldConvert(
        _ character: Character,
        at index: Int,
        in characters: [Character],
        sourceLanguage: LanguageID
    ) -> Bool {
        if character.isLetter {
            return true
        }
        guard sourceLanguage == .en || sourceLanguage == .ro else {
            return false
        }
        guard Self.englishSymbolLetters.contains(character) else {
            return false
        }
        let hasConvertibleBefore = characters[..<index].reversed().contains { previous in
            if previous.isWhitespace || previous.isNewline { return false }
            return previous.isLetter || Self.englishSymbolLetters.contains(previous)
        }
        let hasConvertibleAfter = characters[(index + 1)...].contains { next in
            if next.isWhitespace || next.isNewline { return false }
            return next.isLetter || Self.englishSymbolLetters.contains(next)
        }
        return hasConvertibleBefore && hasConvertibleAfter
    }

    /// Converts buffer of key events into string for requested language layout.
    func render(_ chars: [WordChar], in language: LanguageID) -> String {
        var result = ""
        result.reserveCapacity(chars.count)
        let resolved = Self.resolvedLanguage(language)
        for char in chars {
            guard let entry = Self.table[char.keyCode] else { continue }
            let base: Character
            switch resolved {
            case .en: base = entry.en
            case .ru: base = entry.ru
            case .uk: base = Self.ukCharacter(for: char.keyCode, fallback: entry.ru)
            default: continue
            }
            let shifted = char.flags.contains(.maskShift)
            let capsLocked = char.flags.contains(.maskAlphaShift)
            let useUpper = shifted != capsLocked
            let scalar = useUpper ? Character(base.uppercased()) : base
            result.append(scalar)
        }
        return result
    }

    /// Keycodes whose output is punctuation in one layout but a letter in another.
    /// Derived automatically from the mapping table so every new layout pair
    /// only needs to update `table`, not maintain a separate symbol list.
    var ambiguousWordInternalKeyCodes: Set<CGKeyCode> {
        var result = Set<CGKeyCode>()
        for (code, entry) in Self.table {
            let ukChar = Self.ukCharacter(for: code, fallback: entry.ru)
            let chars = [entry.en, entry.ru, ukChar]
            let hasPunct = chars.contains { $0.isPunctuation }
            let hasLetter = chars.contains { $0.isLetter }
            if hasPunct && hasLetter {
                result.insert(code)
            }
        }
        return result
    }

    /// All characters reachable through ambiguous keycodes, for fast membership checks.
    var ambiguousWordInternalCharacters: Set<Character> {
        var result = Set<Character>()
        for code in ambiguousWordInternalKeyCodes {
            guard let entry = Self.table[code] else { continue }
            let ukChar = Self.ukCharacter(for: code, fallback: entry.ru)
            result.formUnion([entry.en, entry.ru, ukChar])
        }
        return result
    }

    /// Shared EN/RU mapping table. UA glyphs are derived from this row's RU
    /// column, with per-keycode overrides defined in `KeyboardMapping+Ua.swift`.
    private static let table: [CGKeyCode: (en: Character, ru: Character)] = [
        0:  ("a", "ф"),
        1:  ("s", "ы"),
        2:  ("d", "в"),
        3:  ("f", "а"),
        4:  ("h", "р"),
        5:  ("g", "п"),
        6:  ("z", "я"),
        7:  ("x", "ч"),
        8:  ("c", "с"),
        9:  ("v", "м"),
        11: ("b", "и"),
        12: ("q", "й"),
        13: ("w", "ц"),
        14: ("e", "у"),
        15: ("r", "к"),
        16: ("y", "н"),
        17: ("t", "е"),
        31: ("o", "щ"),
        32: ("u", "г"),
        34: ("i", "ш"),
        35: ("p", "з"),
        37: ("l", "д"),
        38: ("j", "о"),
        40: ("k", "л"),
        45: ("n", "т"),
        46: ("m", "ь"),
        // Cyrillic-specific keys mapped to QWERTY symbols when typed in EN
        33: ("[", "х"),
        30: ("]", "ъ"),
        41: (";", "ж"),
        39: ("'", "э"),
        43: (",", "б"),
        47: (".", "ю"),
        50: ("`", "ё")
    ]

    private static let englishSymbolLetters: Set<Character> = ["[", "]", ";", "'", ",", ".", "`"]
}
