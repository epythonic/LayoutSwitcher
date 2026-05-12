# LayoutSwitcher — Roadmap

Приложение-аналог Punto Switcher / Caramba Switcher для macOS 15 Sequoia+. Автоматически определяет, что пользователь печатает в неверной раскладке, удаляет ошибочно набранное слово, переключает раскладку и перепечатывает слово в правильной.

## Context

**Зачем:** Штатный macOS не имеет автопереключателя раскладки. Punto Switcher от Яндекса больше не обновляется, Caramba устарел. Нужна современная замена на Swift под Sequoia.

**Что уже есть:** [LayoutSwitcher](../) — чистый SwiftUI-шаблон с `WindowGroup`, `ContentView`, SwiftData `Item`. Deployment target macOS 15.7, App Sandbox включён, entitlements не заданы. Весь шаблонный код будет удалён — для утилиты он не нужен.

**Ключевые технические ограничения:**

- `CGEventTap` требует Accessibility permission и **несовместим с App Sandbox** → MAS-дистрибуция невозможна, только Developer ID + Notarization.
- `CGEventTap` callback крутится на main run loop → тяжёлый анализ должен уходить на фоновую очередь.
- На macOS 15 TCC-гранты могут сбрасываться при обновлениях и смене подписи → нужен живой poll статуса.
- Переключение раскладки — Carbon `TISSelectInputSource`; синтез клавиш — `CGEvent.post`; обратное отображение символ→keyCode — `UCKeyTranslate`.

**Стратегия поставки:** тонкий MVP сначала, потом расширение.

- **MVP (milestone M1)** — Phase 0→7, только RU↔EN, минимум UI. Работает автопереключение в TextEdit/Safari. ~3–4 недели. Цель — убедиться, что архитектурный костяк и retyping-движок жизнеспособны.
- **Feature complete (M2)** — Phase 8→12, включая добавление пар UA↔EN и DE↔EN поверх generic-архитектуры. ~3 недели.
- **Release candidate (M3)** — Phase 13→14(+15). Signing/notarization/DMG/Sparkle. **Phase 14 опциональна** — делается только если принято решение публиковать; до этого MVP запускается локально через ad-hoc signing.

**Архитектурное решение по языкам:** в v1.0 активна пара RU↔EN, но все соответствующие модули (`LayoutPair`, `KeyboardMapping`, `WordDictionary`, `NGramModel`, `LayoutDetector`) проектируются как generic — добавление UA/DE в позднейших фазах = новые таблицы + словари без рефакторинга кода. Цена: +1–2 дня в Phase 5–6.

**Примерный объём:** ~45–60 дней фокусированной работы (9–12 календарных недель для одного разработчика). Полный релиз с 4 парами и публикацией: добавить ~5–7 дней.

---

## Phase 0 — Подготовка проекта (1.5 дня)

**Цель:** собирающийся sandbox-free скелет menu-bar агента без SwiftData и `WindowGroup`.

### Задачи

- Удалить шаблонный код: [Item.swift](../Item.swift), [ContentView.swift](../ContentView.swift).
- Переписать [LayoutSwitcherApp.swift](../LayoutSwitcherApp.swift): убрать SwiftData и `WindowGroup`, использовать `@NSApplicationDelegateAdaptor(AppDelegate.self)` + `Settings { EmptyView() }`.
- В `LayoutSwitcher.xcodeproj/project.pbxproj`:
  - `ENABLE_APP_SANDBOX = NO` (обе конфигурации).
  - `INFOPLIST_KEY_LSUIElement = YES` — скрыть из Dock, режим accessory.
  - `INFOPLIST_KEY_LSMinimumSystemVersion = 15.0`.
  - Убрать неиспользуемые `REGISTER_APP_GROUPS`, `ENABLE_USER_SELECTED_FILES`.
- Создать `LayoutSwitcher/LayoutSwitcher.entitlements`:
  - `com.apple.security.app-sandbox = false`
  - `com.apple.security.device.input-monitoring = true`
  - Позже (Phase 14) — hardened-runtime ключи.
- Структура папок под `LayoutSwitcher/`:
  - `App/` — `LayoutSwitcherApp.swift`, `AppDelegate.swift`, `AppState.swift`
  - `Core/EventTap/`, `Core/Typing/`, `Core/Layout/`, `Core/Detection/`, `Core/Permissions/`, `Core/Exclusions/`, `Core/Hotkeys/`, `Core/AppContext/`, `Core/Stats/`
  - `Features/MenuBar/`, `Features/Settings/`, `Features/Onboarding/`
  - `Resources/Dictionaries/`, `Resources/Localizations/`

**Готово когда:** `xcodebuild -scheme LayoutSwitcher build` проходит, приложение стартует без окон и без иконки в Dock, `print()` из `applicationDidFinishLaunching` видно в консоли.

---

## Phase 1 — Menu bar каркас (2 дня)

**Цель:** рабочий `NSStatusItem` с меню (Enable/Disable, Preferences, Quit) и окном настроек.

### Задачи

- `Features/MenuBar/StatusItemController.swift` — `NSStatusBar.system.statusItem`, template icon (`SF Symbols "keyboard"`), программное `NSMenu` (без `MenuBarExtra` — нужен контроль).
- `Features/Settings/SettingsWindowController.swift` — single-instance `NSWindowController` с `NSHostingController<SettingsView>`.
- `Features/Settings/SettingsView.swift` — `TabView` с вкладками: General / Layouts / Hotkeys / Exclusions / Dictionaries / About.
- `App/AppState.swift` — `@Observable` синглтон: `isEnabled`, `currentLayout`, `lastAction`.

**Подводные камни:**

- `LSUIElement = YES` не даёт окну стать ключевым → вызывать `NSApp.activate(ignoringOtherApps: true)` руками при открытии Preferences.

**Готово когда:** иконка в статус-баре, меню открывается, Preferences окно открывается/закрывается, Quit работает.

---

## Phase 2 — Accessibility permission flow (2 дня)

**Цель:** onboarding запрашивает AX, открывает System Settings, ждёт разрешение live, реагирует без перезапуска.

### Задачи

- `Core/Permissions/AccessibilityPermission.swift`:
  - `AXIsProcessTrusted()` / `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`.
  - Deep-link: `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.
  - Poll каждую секунду пока не гранд, публиковать изменение через Combine/NotificationCenter.
- `Core/Permissions/InputMonitoringPermission.swift` — `IOHIDCheckAccess` как fallback (нужен только при `.cghidEventTap`).
- `Features/Onboarding/OnboardingWindow.swift` — SwiftUI-пейджер: Welcome → Accessibility → Layouts → Hotkey → Done.

**Подводные камни:**

- После гранта нужно **пересоздавать event tap** — существующий не активируется ретроактивно.
- На Sequoia ad-hoc подписанный debug-билд иногда требует quit+relaunch после гранта — UX должен это учитывать.

**Готово когда:** на холодном старте без AX показан onboarding; после гранта приложение переходит в "ready" без перезапуска.

---

## Phase 3 — CGEventTap скелет (3 дня)

**Цель:** глобальный перехват `keyDown` и `flagsChanged`, логирование, pass-through. Без логики.

### Задачи

- `Core/EventTap/KeyboardEventTap.swift`:
  - `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, …)` — **`.defaultTap` обязателен**, `.listenOnly` не даст потом модифицировать.
  - `eventsOfInterest = (1 << keyDown) | (1 << flagsChanged) | (1 << leftMouseDown) | (1 << rightMouseDown)`.
  - Callback — C-функция, `self` передаётся через `Unmanaged.passUnretained(self).toOpaque()` в `userInfo`.
  - `CFMachPortCreateRunLoopSource` + `CFRunLoopAddSource(CFRunLoopGetMain(), …, .commonModes)`.
- Обработка `.tapDisabledByTimeout` / `.tapDisabledByUserInput` — реактивация `CGEvent.tapEnable(tap:enable:true)`.
- `Core/EventTap/KeyEvent.swift` — value type: `keyCode`, `flags`, unicode (`CGEvent.keyboardGetUnicodeString`), timestamp, PID.
- Lifecycle: (пере)создание tap при flip AX=true, teardown при disable.

**Подводные камни:**

- **Не блокировать callback** — >~1с → macOS отключит tap. Анализ — на выделенной `DispatchQueue`.
- **Secure input** (`IsSecureEventInputEnabled()`) — пароли глушат все tap'ы системно. Детектить и показывать индикатор в menu bar.
- Фильтровать autorepeat (`CGEventField.keyboardEventAutorepeat == 1`).

**Готово когда:** печать 100 клавиш в Chrome → 100 логов с правильным unicode, ввод не тормозит.

---

## Phase 4 — Word buffer + focus tracking (3 дня)

**Цель:** буфер текущего слова + понимание, в каком приложении/поле печатаем.

### Задачи

- `Core/Typing/WordBuffer.swift`:
  - `characters: [WordChar]` где `WordChar = { keyCode, unicode, flags, layoutID, timestamp }`.
  - `append` — если `Character.isLetter`, иначе `commit(separator:)`.
  - `reset(reason:)` на: смене app, клике мыши, Esc, стрелках.
  - Хранить последнее закоммиченное слово для undo/хоткея.
- `Core/Typing/WordSeparator.swift` — `enum { space, enter, tab, punctuation, navigation, control }`.
- `Core/AppContext/FocusedAppObserver.swift`:
  - `NSWorkspace.didActivateApplicationNotification` — reset + запомнить bundleID.
  - AX: `AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute, …)` → проверка `AXRole == "AXSecureTextField"` → не буферизовать.
- Combine `PassthroughSubject<WordEvent, Never>`: `.appended / .committed / .reset`.

**Подводные камни:**

- **IME / dead keys**: `keyboardGetUnicodeString` возвращает raw char до композиции. При активном IME (японский, китайский, marked text) — не буферизовать.
- **Backspace внутри слова** — удалить последний символ буфера, не коммитить.
- **Cmd+V** — хард-ресет, не знаем что вставлено.
- **Модификаторы одни**: Shift/Cmd без буквы — игнорировать, не ресетить буфер.

**Готово когда:** "hello world" → два commit-события; `backspace` после "hell" → буфер="hel"; клик мышкой → reset без коммита.

---

## Phase 5 — Input Source (TIS) wrapper (2 дня)

**Цель:** чтение текущей раскладки, список установленных, программное переключение, подписка на изменение.

### Задачи

- `Core/Layout/InputSource.swift` — враппер над `TISInputSource`: `id`, `localizedName`, `languageCode`, `isEnabled`, `isSelectable`, `icon` (`TISCopyImage`).
- `Core/Layout/InputSourceManager.swift`:
  - `current()` — `TISCopyCurrentKeyboardInputSource`.
  - `allKeyboardLayouts()` — `TISCreateInputSourceList(filter: kTISCategoryKeyboardInputSource)`.
  - `select(_:)` — `TISSelectInputSource`.
  - Darwin notification `kTISNotifySelectedKeyboardInputSourceChanged` → `@Published currentInputSource`.
- `Core/Layout/LayoutPair.swift` — `{ primary, alternate, languagePair: LanguagePair }`. Generic: в MVP один активный pair (RU↔EN), но коллекция `[LayoutPair]` хранится в настройках, детектор принимает её на вход и работает по всем парам. В v1.1 добавление UA↔EN и DE↔EN = новая запись + таблица, без изменений логики.
- `Core/Layout/LanguagePair.swift` — `enum { ruEn, ukEn, deEn, … }` с ассоциированными `KeyboardMapping` и `[WordDictionary]`.

**Подводные камни:**

- `TIS*` возвращают `Unmanaged` — `.takeRetainedValue()` на `Copy/Create`, `.takeUnretainedValue()` на `Get`.
- `TISSelectInputSource` молча не переключит, если источник не в списке активных (System Settings → Keyboard → Input Sources).
- Отфильтровать IME от raw layouts по `kTISPropertyInputSourceType == kTISTypeKeyboardLayout`.

**Готово когда:** menu bar live-обновляется при ручной смене через системное меню и наоборот.

---

## Phase 6 — Детектор языка и транслитерация (6 дней)

**Цель:** чистый модуль, который по слову + активной раскладке решает — менять или нет.

### Задачи

- `Core/Detection/KeyboardMapping.swift`:
  - **Generic протокол** `KeyboardMapping` с методом `transliterate([WordChar], to: LayoutID) -> String`.
  - Реализация `RuEnQwertyMapping` — статические таблицы ЙЦУКЕН ↔ US QWERTY **по `CGKeyCode`** (не по unicode — Option-модификаторы дают другой вывод).
  - В v1.0 активна только `RuEnQwertyMapping`. В v1.1 добавляются `UaEnQwertyMapping`, `DeQwertzMapping` без изменений вызывающего кода.
- `Core/Detection/Dictionary/WordDictionary.swift` — протокол; реализации `InMemoryTrieDictionary`, `BloomFilterDictionary`.
- `Resources/Dictionaries/`:
  - `ru.txt` — ~200k лемм+форм (OpenCorpora / hunspell `ru_RU`).
  - `en.txt` — ~100k (SCOWL size 60).
  - **Build-time компиляция в `.bin`** через Swift Package `DictionaryBuilder` (Run Script Build Phase) — < 50MB на диске, startup < 200 мс.
- `Core/Detection/NGramModel.swift` — character bigram log-prob таблицы для RU и EN, fallback на OOV (имена, неологизмы).
- `Core/Detection/LayoutDetector.swift` — оркестратор:

  ```
  raw = buffer.asTyped()                      // "ghbdtn"
  flipped = transliterate(buffer, alt)        // "привет"
  rawValid  = dict[active].contains(raw)  || ngram[active].score(raw)  > τ
  flipValid = dict[alt].contains(flipped) || ngram[alt].score(flipped) > τ
  if rawValid && !flipValid → .keep
  if !rawValid && flipValid → .switchAndRetype(flipped, altLayout)
  if !rawValid && !flipValid → .ambiguous
  if rawValid && flipValid → .keep (доверяем)
  ```

- `Core/Detection/Thresholds.swift` — `τ`, min-length=3, max-length=30, ignore-digits-symbols.
- Unit-тесты: `LayoutDetectorTests.swift` с golden set (~100 слов).

**Подводные камни:**

- Короткие слова "и", "а" — min length 3.
- Проприетарные имена (iPhone, Lenin) — ngram должен спасать; иначе пользовательский словарь.
- Ё/Е — нормализация на lookup, сохранение оригинала при retype.
- Цифры внутри слова ("iPhone15") — ambiguous, пропуск.

**Готово когда:** unit-тесты проходят ≥95%, детекция < 1 мс на слово на M-серии.

---

## Phase 7 — Retyping engine (4 дня)

**Цель:** удалить слово backspace'ами, переключить раскладку, напечатать заново.

### Задачи

- `Core/Typing/Retyper.swift`:
  1. Синтез N+1 backspace (N = length слова + 1 за separator).
  2. `TISSelectInputSource(target)` → ждать Darwin-notification (semaphore, timeout 150 мс).
  3. Для каждого символа правильного слова: `UCKeyTranslate` (обратный) → `(keyCode, modifiers)` → `CGEvent(keyboardEventSource:virtualKey:keyDown:)` + `.post(tap: .cghidEventTap)`.
  4. Re-insert separator.
- `Core/Typing/SyntheticEventFilter.swift`:
  - Теггинг синтетических событий через `setIntegerValueField(.eventSourceUserData, value: MAGIC)`.
  - Tap callback: если `MAGIC` — pass-through без буферизации.
- `Core/Typing/KeyCodeEncoder.swift` — кэш `character → (keyCode, modifiers)` на input-source.
- `Core/TypingPipeline.swift` — оркестратор между `WordBuffer` и `Retyper`.

**Подводные камни:**

- **Гонка между сменой раскладки и retyping** — ждать notification.
- **Hardened apps** (1Password, банки) отклоняют синтетические события — не крашить, graceful fail.
- **Caps Lock** — сохранить до, восстановить после.
- **Пользователь продолжает печатать** во время retyping (<50 мс) — дропать новые события с логом.
- **Undo-стек target-приложения** пачкается — документировать как known limitation (у Punto тоже так).

**Готово когда:** в TextEdit, Notes, Safari, VS Code: `ghbdtn ` → `привет `, иконка флипается. В Terminal/password field — ничего.

---

## Phase 8 — Горячие клавиши (1.5 дня)

**Цель:** ручной триггер конвертации последнего слова + отмена авто-свитча.

### Задачи

- `Core/Hotkeys/HotkeyRegistry.swift` — Carbon `RegisterEventHotKey` (надёжнее для single-key combos типа Break/Pause).
- `Core/Hotkeys/ActionCoordinator.swift`:
  - `.manualToggleLast` — взять `lastCommittedWord`, транслитерировать, retype.
  - `.undoLastAutoSwitch` — реверс последнего `Retyper` действия в окне 3 с.
- Settings → Hotkeys tab: `KeyRecorderView` (custom `NSViewRepresentable` ловит `NSEvent`).
- Персист через `@AppStorage`.

**Default hotkey:** `⌃⌥\` (Break/Pause на Apple клавиатурах нет).

**Готово когда:** пользователь настраивает хоткей, жмёт где угодно → последнее слово флипается; undo работает межпроцессно.

---

## Phase 9 — Исключения приложений (1 день)

### Задачи

- `Core/Exclusions/ExclusionList.swift` — `Set<BundleID>` в UserDefaults, дефолты: `com.apple.Terminal`, `com.googlecode.iterm2`, `com.microsoft.VSCode`, `com.jetbrains.*`, `com.1password.1password`.
- `TypingPipeline` чекает `ExclusionList.isExcluded(currentBundleID)` перед `Retyper` (детектор продолжает работать для хоткея).
- Settings → Exclusions tab: список + `NSOpenPanel` "+ Add App…".
- **Всегда пропускать** `AXSecureTextField` независимо от списка.

---

## Phase 10 — Пользовательский словарь, статистика, настройки (2 дня)

### Задачи

- `Core/Detection/Dictionary/UserDictionary.swift` — JSON в `~/Library/Application Support/LayoutSwitcher/user-dict-{lang}.json`, проверяется **первым** в `LayoutDetector` (перебивает false positives).
- `Core/Stats/UsageStats.swift` — счётчики: `autoSwitches`, `manualSwitches`, `wordsTyped`, `charactersSaved`. Дневной + all-time.
- Settings → Dictionaries tab: редактор + импорт `.txt`.
- Settings → General tab: master toggle, launch-at-login, опциональная нотификация на свитч.

---

## Phase 11 — Полировка UI настроек и onboarding (2 дня)

### Задачи

- Все табы с реальным контентом, валидацией, live preview.
- Onboarding: Welcome → AX → выбор пары раскладок → хоткей → "Try it out" sandbox.
- Menu bar dropdown: submenu "Recent auto-switches" (последние 10) с "Add to exceptions" inline.
- SF Symbols, соответствие macOS 15 visual idioms.

---

## Phase 12 — Локализация RU/EN (1 день)

### Задачи

- `Localizable.xcstrings` (String Catalog), `InfoPlist.xcstrings` для имени приложения.
- Все строки через `String(localized:)` / `Text("key")`.
- Полный русский перевод.

---

## Phase 13 — Тестирование (3 дня)

### Задачи

- **Unit** в `LayoutSwitcherTests/`:
  - `LayoutDetectorTests` (golden set).
  - `KeyboardMappingTests` (round-trip для всех клавиш).
  - `WordBufferTests` (backspace, separators, resets).
  - `NGramModelTests` (monotonicity).
- **Интеграция** (ручная, `TESTING.md`): TextEdit, Notes, Safari, Chrome, VS Code, Xcode, Terminal, iTerm2, Slack, Telegram, Mail, Word, 1Password.
- **Edge cases**: быстрый набор, микс-язык, emoji, URL, пароли (MUST NOT switch), IME, dead keys (`Option+E` → é).
- **Стресс**: 10k keystrokes/60с через osascript, Instruments — утечки, drift.

---

## Phase 13.5 — Расширение до UA↔EN и DE↔EN (3–4 дня, выполняется после M2)

**Цель:** добавить украинскую и немецкую пары поверх generic-инфраструктуры Phase 5–6.

### Задачи

- `Core/Detection/KeyboardMapping+Ua.swift` — таблица украинской раскладки ↔ QWERTY (отличия от RU: `і`/`ї`/`є`/`ґ`, нет `ё`/`ъ`/`ы`/`э`).
- `Core/Detection/KeyboardMapping+De.swift` — немецкая QWERTZ ↔ US QWERTY (y↔z swap, `ä`/`ö`/`ü`/`ß` на спец-позициях). Сопряжённая раскладка — US QWERTY, не RU.
- Словари `Resources/Dictionaries/uk.bin`, `de.bin` — прогнать через `DictionaryBuilder` (~100k слов каждый, SCOWL/hunspell `uk_UA`, `de_DE`).
- `NGramModel` bigram-таблицы для uk и de.
- Settings → Layouts tab: UI добавления активных пар из установленных системных раскладок.
- Расширить unit-тесты golden-set на ~30 слов/пара.

**Подводные камни:**

- DE QWERTZ — это не просто другая буква на месте RU-раскладки, у него swap y↔z. Тесты на round-trip обязательны.
- Украинский похож на русский — риск false positive между ними. Если у пользователя активны обе (RU и UA), учитывать в `LayoutDetector` как отдельные пары с более консервативным порогом.

**Готово когда:** `"ghbdtn"` на EN + активной паре UA↔EN пытается транслитерировать в UA, не находит в словаре → `.ambiguous`; `"sld"` на DE → корректная детекция.

---

## Phase 14 — Подпись, нотаризация, дистрибуция (2 дня, ОПЦИОНАЛЬНО)

**Выполняется только если принято решение публиковать приложение.** Для личного использования достаточно ad-hoc signing, которое Xcode делает автоматически при Debug-билде — приложение запустится на машине разработчика без дополнительной настройки.

### Задачи

- Developer ID Application сертификат, `CODE_SIGN_STYLE = Manual`, `DEVELOPMENT_TEAM`.
- `ENABLE_HARDENED_RUNTIME = YES` + `app-sandbox = false` (корректная комбинация для CGEventTap-утилит).
- Archive → export → `xcrun notarytool submit … --wait` → `xcrun stapler staple`.
- DMG через `create-dmg` с drag-to-Applications.
- **Sparkle** (Swift Package): EdDSA, `SUPublicEDKey` в Info.plist, appcast на GitHub Pages, `cs.disable-library-validation` для XPC Sparkle-хелперов.

**Подводные камни:**

- Первая нотаризация обычно падает — диагностика через `xcrun notarytool log <id>`.
- **MAS путь закрыт навсегда** (sandbox-off + CGEventTap).

**Готово когда:** `spctl -a -vvv LayoutSwitcher.app` = accepted/notarized; DMG запускается на чистом macOS 15; Sparkle-апдейт end-to-end работает.

---

## Phase 15 — Полировка (1.5 дня, опционально для v1.0)

- Launch at login: `SMAppService.mainApp.register()`.
- App icon: полный `.icns`, варианты status-icon (RU/EN/disabled/secure-input).
- `UNUserNotificationCenter` уведомление при auto-switch с Undo action.
- `os.Logger(subsystem: "GIH.LayoutSwitcher")` + "Export Logs" для багрепортов.

---

## Milestone cuts

- **M1 — Thin MVP** (end of Phase 7, ~3–4 недели): RU↔EN работает в TextEdit/Safari, запускается локально через ad-hoc Xcode debug build. Отсутствуют: хоткеи, exclusions, multi-language UI, нотаризация. Это демо для себя.
- **M2 — Feature complete** (end of Phase 12, ~6–7 недель суммарно): RU↔EN с полным UX — хоткеи, exclusions, пользовательский словарь, статистика, локализация.
- **M2.5 — Multi-language** (end of Phase 13.5, ~8 недель): добавлены UA↔EN и DE↔EN.
- **M3 — Release** (end of Phase 14+15, ~9–12 недель): нотаризованный DMG, Sparkle, launch-at-login, полный icon set. Выполняется только если принято решение о публикации.

---

## Верификация end-to-end

1. **Build**: `xcodebuild -scheme LayoutSwitcher -configuration Debug build` — без ошибок.
2. **Unit**: `xcodebuild test -scheme LayoutSwitcher` — LayoutDetector и WordBuffer зелёные.
3. **Ручной smoke test** по сценариям:
   - Свежий запуск без AX → onboarding ведёт до гранта и затем до рабочего состояния без перезапуска.
   - В TextEdit на EN: `ghbdtn<space>` → `привет<space>`, menu-bar icon → RU.
   - В TextEdit на RU: `руддщ<space>` → `hello<space>`, menu-bar icon → EN.
   - В Terminal: `ghbdtn<space>` → остаётся как есть (исключение).
   - В `AXSecureTextField` (пароль Safari): ничего не меняется.
   - Хоткей `⌃⌥\` после `iPhone<space>` — флипает; undo в окне 3с возвращает.
   - Смена фокуса мышкой посреди слова — не коммитит мусор.
4. **Notarization**: `spctl -a -vvv` на финальном `.app`.

## Риск-лист

1. **Hardened apps отвергают синтетические события** → exclusion list + graceful fail.
2. **TCC сбрасывается после обновлений macOS** → on-launch trust check + UX re-grant.
3. **`TISSelectInputSource` будущие ограничения** → абстракция через `InputSourceManager`, AppleScript fallback.
4. **Детектор false-positives на именах/микс-языке** → min-length, user-dict auto-learning на undo, тюнингуемые пороги.
5. **Нотаризация sandbox-off + hardened** → пройти рано на тестовом app, `--force --options runtime --deep`.

## Критические файлы

- `LayoutSwitcher/App/LayoutSwitcherApp.swift` — точка входа, AppDelegate
- `LayoutSwitcher/Core/EventTap/KeyboardEventTap.swift` — сердце перехвата
- `LayoutSwitcher/Core/Detection/LayoutDetector.swift` — алгоритмический центр
- `LayoutSwitcher/Core/Typing/Retyper.swift` — выполнение коррекции
- `LayoutSwitcher/Core/Layout/InputSourceManager.swift` — обёртка над TIS
- `LayoutSwitcher/LayoutSwitcher.entitlements` — без sandbox, hardened runtime
- `LayoutSwitcher.xcodeproj/project.pbxproj` — sandbox off, LSUIElement
