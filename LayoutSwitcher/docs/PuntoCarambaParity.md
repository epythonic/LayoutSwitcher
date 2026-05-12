# LayoutSwitcher — Punto / Caramba parity & beyond

Полная карта функциональности Punto Switcher и Caramba Switcher с разметкой нашего текущего покрытия и плана: что догонять, что добавлять сверх, в каком порядке.

Документ — рабочий план, не маркетинговый список. Каждая фича снабжена тегом текущего состояния, оценкой трудозатрат и приоритетом. Реализация идёт в порядке приоритетов P0 → P3 на основе cost / value.

**Актуализировано:** 2026-04-27 после реализации Negative Learning, UI learned exceptions, Sound Feedback, URL/email guard, Force-retype last word, Visual flash и tray layout badge.

## Легенда

- **Status**
  - `DONE` — реализовано, есть тесты.
  - `PARTIAL` — частично есть (есть инфраструктура, нет полной фичи).
  - `MISSING` — нет вообще.
  - `BETTER` — у нас лучше, чем у конкурентов; держим как преимущество.
- **Effort** — грубая оценка в человеко-днях.
- **Priority**
  - `P0` — закрывает реальный пользовательский pain, ставим в ближайший спринт.
  - `P1` — заметная фича, в следующий релиз.
  - `P2` — nice-to-have, в бэклог.
  - `P3` — спекулятивно, может никогда не понадобиться.

---

## 1. Авто-переключение раскладки (ядро)

### 1.1. Per-word detection (печать в потоке)

- **Status:** DONE.
- LayoutDetector + WordBuffer + Retyper. NGramModel + NSSpellChecker + UserDictionary + RomanianDiacriticResolver. Tie-break детерминированный, NL-скорер для loanwords.

### 1.2. Per-word detection с курсором в середине строки

- **Status:** MISSING.
- Punto/Caramba умеют: пользователь поставил курсор внутрь старого слова, начал печатать → переключают это слово.
- У нас WordBuffer сбрасывается при смене фокуса/мыши; курсор внутрь существующего слова → детектор не работает.
- **План:** AX-наблюдение за `kAXSelectedTextRangeAttribute` фокусированного элемента. При курсорной позиции внутри уже существующего слова считывать его через AX, дополнять до WordBuffer'а синтетически и продолжать обычный пайплайн.
- **Effort:** 4–5 дней (AX-нюансы, поддержка нестабильных приложений типа Electron).
- **Priority:** P1.

### 1.3. Конфигурируемая агрессивность детектора

- **Status:** DONE.
- `DetectionSensitivity` (low/medium/high) уже есть. Threshold-параметры покрывают порог длины, NL-скоринг, n-грамм-разрыв.

### 1.4. Bundle-aware undo автосвитча

- **Status:** DONE.
- `AutoSwitchRecord.bundleID` + проверка при undo. Punto иногда «откатывает» в чужом приложении, у нас — никогда.

### 1.5. Negative learning (пользователь отменил → запомнить)

- **Status:** DONE.
- Punto/Caramba: после ⌘Z за авто-свитчем добавляют слово в негативный кеш на N часов / навсегда.
- **Реализовано:**
  1. `LearningCache` сохраняет точную пару `(bundleID, original, corrected, sourceLanguage, targetLanguage)` с TTL и capacity.
  2. `HotkeyCoordinator` записывает исключение только после успешного undo retype.
  3. `TypingPipeline` подавляет совпавший auto-switch до destructive retype, без stats/recents.
  4. Settings → `Learned exceptions`: просмотр, удаление выбранного исключения, `Clear all`.
- **Tests:** `LearningCacheTests`, `HotkeyCoordinatorTests`, `TypingPipelineTests`.
- **Effort:** done.
- **Priority:** P0. Это превращает одноразовую отмену в обучение и резко снижает раздражение.

### 1.6. Force-retype last word (хоткей)

- **Status:** DONE.
- Punto: Pause = «переключи последнее слово независимо от детектора, я знаю лучше».
- **Реализовано:**
  1. Новый `HotkeyAction.forceRetypeLastWord`.
  2. Default binding: `⌃⌥⇧\`.
  3. `HotkeyCoordinator` переиспользует транзакционный `Retyper` для последнего `WordBuffer.lastCommitted`.
  4. Сохранены guard-ы: 3-секундное окно, bundle-aware контекст, запись stats/recents только после успешного retype.
  5. Settings → Hotkeys и HelpContent показывают новый хоткей.
- **Tests:** `HotkeyRegistryTests`, `HotkeyCoordinatorTests`.
- **Effort:** done.
- **Priority:** P0.

### 1.7. Cooldown / антидребезг

- **Status:** DONE.
- **Реализовано:**
  1. Transient runtime cooldown после successful auto-switch (1.5 секунды).
  2. Повторная идентичная correction в том же bundleID/targetLanguage suppress'ится до истечения cooldown.
  3. Cooldown очищается на focus/navigation/escape/mouse click/modifier shortcut/reset paths.
  4. Clock injection для тестов без Task.sleep.
- **Tests:** TypingPipeline cooldown regression tests (repeatedIdenticalAutoSwitchIsSuppressedDuringCooldown, identicalAutoSwitchRunsAgainAfterCooldownExpires, failedRetypeDoesNotArmAutoSwitchCooldown, focusChangeClearsAutoSwitchCooldown).
- **Effort:** done.
- **Priority:** P1.

### 1.8. URL/email/handle as guard

- **Status:** DONE.
- Punto/Caramba знают, что `https://`, `gmail.com`, `@user`, `git@github.com`, путь файла — не надо свитчить.
- **Реализовано:** `NonConvertibleTokenGuard` в `LayoutDetector` + live-pipeline suppression для technical compound tokens после `@`, `.`, `/`, `\`, `:` и `_`.
- **Effort:** 1 день + тесты.
- **Priority:** P0.

### 1.9. Cap delay перед свитчем («не свитчить пока активно печатает»)

- **Status:** DONE.
- Punto имеет настройку «свитч только после паузы N мс».
- **Реализовано:**
  1. `AppState.waitForTypingPauseEnabled` (Bool) и `AppState.typingPauseDelayMilliseconds` (Int, 100–1000 ms, default 250 ms).
  2. Settings → Detection: Toggle «Wait for typing pause before auto-switch» и Stepper для настройки задержки.
  3. `TypingPipeline.pendingEvaluationTask` и `pendingCommittedWord` для хранения состояния отложенной оценки.
  4. `TypingPipeline.scheduleEvaluation(_:)` — если флаг включён, откладывает `evaluate(_:)` на configured delay через `Task.sleep`.
  5. `TypingPipeline.cancelPendingEvaluation()` — отменяет отложённую задачу и очищает слово.
  6. Отмена pending evaluation на: focus change, mouse click, modifier shortcut, navigation keys, escape, backspace, новая буква.
  7. Cooldown корректно применяется после delayed auto-switch.
  8. Persistence и clamping значений через UserDefaults.
- **Tests:** `AppStateTests.typingPauseDelayPersistsAndClamps`, `TypingPipelineTests.typingPauseDelayDisabledEvaluatesImmediately`, `TypingPipelineTests.typingPauseDelayEnabledWaitsBeforeEvaluation`.
- **Effort:** done.
- **Priority:** P2.

### 1.10. Поддержка цифрового ряда и пунктуации

- **Status:** DONE.
- Уже закрыто: punctuation-safe retype через Unicode-событие после layout switch, Enter/Tab не запускают auto-switch, цифра внутри слова poison/reset-ит текущий token, digit tokens не перепечатываются как partial corrupted state.
- **Реализовано:**
  1. Digit row (1-0) классифицируется как `.digit` и вызывает `suppressUntilSeparator = true` + reset буфера, предотвращая коррекцию токенов с цифрами (версии, коды, ID).
  2. Non-ambiguous punctuation (!, ?, :, ", (, ), {, }, <, >) классифицируется через Unicode как `.separator(.punctuation)` и коммитит слово.
  3. Ambiguous punctuation-shaped keys ([, ], ;, ', ,, ., `) могут обрабатываться как`.letter` через `ambiguousWordInternalKeyCodes` в `TokenBoundaryPolicy`, если они являются буквами в другой поддерживаемой раскладке. Это предотвращает разрыв слов при печати в неправильной раскладке.
  4. Enter (keyCode 36, 76) и Tab (keyCode 48) коммитят слово, но подавляют auto-switch в `TypingPipeline.evaluate` (предотвращает отправку сообщения до отмены).
  5. Separator preservation: `WordBuffer` сохраняет `separatorKeyCode` и `separatorFlags` в `CommittedWord`. `Retyper` использует key events для non-printing separators (Space, Enter, Tab), а printable punctuation восстанавливает Unicode-событием после layout switch, чтобы punctuation не была переинтерпретирована как символ целевой раскладки.
  6. Technical-token guard: `NonConvertibleTokenGuard.isTechnicalBoundary` подавляет токены для URL/email/handle patterns (`@`, `.`, `/`, `\`, `:`, `_`).
- **Tests:** `TypingPipelineTests.digitPoisonsTokenUntilSeparator`, `TypingPipelineTests.enterSeparatorCommitsButSuppressesAutoSwitch`, `TypingPipelineTests.tabSeparatorCommitsButSuppressesAutoSwitch`, `TypingPipelineTests.periodCommitsSentenceWordAndSuppressesFollowingTechnicalSuffix`, `TypingPipelineTests.exclamationSeparatorTriggersSafeAutoSwitch`, `TypingPipelineTests.rightParenthesisSeparatorTriggersSafeAutoSwitch`, `RetyperTests.punctuationSeparatorIsRestoredAsUnicodeAfterLayoutSwitch`.
- **Effort:** done.
- **Priority:** P1.

---

## 2. Конвертация выделения / манипуляции с текстом

### 2.1. Convert selection — раскладка

- **Status:** DONE.
- `SelectionConverter` + AX + clipboard fallback. Бьёт punto.

### 2.2. Smart Capitalization («ВЕРХНИЙ» / «нижний» / «Title»)

- **Status:** MISSING.
- Punto: выделить текст → хоткей → переключение между cases (lower → UPPER → Title).
- **План:** новый `HotkeyAction.cycleSelectionCase`, который:
  1. Берёт выделение через AX/clipboard.
  2. Определяет текущий case.
  3. Меняет на следующий по циклу: lower → UPPER → Title → lower.
  4. Применяет обратно.
- **Effort:** 2 дня.
- **Priority:** P1.

### 2.3. Транслитерация (кириллица ↔ латиница)

- **Status:** MISSING.
- Punto: «Привет» → «Privet», «Privet» → «Привет».
- **План:**
  1. Таблицы транслитерации ru↔latin, uk↔latin (ГОСТ или BGN/PCGN — определиться).
  2. `HotkeyAction.transliterateSelection`.
  3. Heuristic для определения исходного направления.
- **Effort:** 3 дня.
- **Priority:** P2 (узкоспециальная, но фанаты Punto её любят).

### 2.4. Reverse case (CapsLock-flip выделения)

- **Status:** MISSING.
- «aBcD» → «AbCd». Тривиально.
- **Effort:** 0.5 дня.
- **Priority:** P3.

### 2.5. Удаление лишних пробелов / нормализация

- **Status:** MISSING.
- Caramba: «удалить двойные пробелы», «убрать пробелы перед знаками препинания».
- **Effort:** 1 день.
- **Priority:** P3.

---

## 3. Auto-replace (автозамены)

### 3.1. Текстовые шорткаты

- **Status:** MISSING.
- Punto AutoText / Caramba autoreplace: `((c))` → `©`, `адр1` → полный адрес, `т.е.` → `то есть`.
- **План:**
  1. Новая модель `AutoReplaceRule { trigger: String, replacement: String, scope: GlobalOrPerLanguage, enabled: Bool }`.
  2. Применение: после коммита WordBuffer (на разделителе) проверять trigger == word; при совпадении — стереть N символов и впечатать replacement.
  3. UI: новая вкладка Settings → Auto-replace со списком правил, импорт/экспорт `.json`.
  4. Дефолтный набор: типографские кавычки, тире, ©/®/™, общие сокращения для RU/EN.
- **Effort:** 5–7 дней (UI крупный).
- **Priority:** P1. Фича большая, но многим пользователям заменяет TextExpander.

### 3.2. Динамические подстановки (дата, буфер обмена, выделение)

- **Status:** MISSING.
- Plain auto-replace + `${date}`, `${time}`, `${clipboard}`.
- **Effort:** +2 дня поверх 3.1.
- **Priority:** P2.

---

## 4. Историчность / журналирование

### 4.1. Diary (журнал всего напечатанного)

- **Status:** MISSING.
- Punto Diary — киллер-фича для многих пользователей: локальный лог всего ввода с поиском.
- **Этический риск:** журнал всего ввода = потенциальная утечка пароля, банковских данных. Нужно делать **очень аккуратно**, по умолчанию **выключено**, исключения по приложениям и по типу поля (любой secure-text поле никогда не пишется).
- **План:**
  1. Опциональный `TypingDiary` (off by default).
  2. Хранение в зашифрованном виде (CryptoKit + key из Keychain).
  3. UI: окно «Diary» с поиском.
  4. Жёсткие исключения: всегда исключать `AXSecureTextField`, и список приложений (1Password, Bitwarden, Keychain Access, Terminal — на выбор пользователя).
  5. TTL: автоудаление записей старше N дней.
  6. Privacy-страница в onboarding: явное подтверждение перед включением.
- **Effort:** 7–10 дней.
- **Priority:** P2 (большая фича + privacy-риск; делать только если есть запрос от пользователей).

### 4.2. Recent auto-switches (текущее)

- **Status:** DONE.
- `RecentSwitches` уже есть.

### 4.3. Statistics

- **Status:** DONE.
- `UsageStats` день / всё время.

---

## 5. UI / UX обратной связи

### 5.1. Звук при авто-свитче

- **Status:** DONE.
- Punto/Caramba: тихий клик — критично для понимания «что-то произошло».
- **Реализовано:** `SoundFeedbackPlayer`, on/off, выбор из 3 системных звуков (`Tink`, `Pop`, `Glass`), preview в Settings, звук только после успешного auto-switch.
- **Tests:** persistence настроек, disabled sound, выбранный sound kind, отсутствие fallback-звука без `AppState`.
- **Effort:** done.
- **Priority:** P0. Самая дешёвая UX-фича.

### 5.2. Visual flash / overlay при авто-свитче

- **Status:** DONE (простой tray-icon вариант).
- Кратковременная подсветка tray-иконки, либо floating mini-toast «RU → EN: hello».
- **Реализовано:** `VisualFeedbackPlayer`, DI в `TypingPipeline`, flash только после успешного auto-switch, настройка on/off и длительности flash в Settings, `StatusItemController.flashTrayIcon()`.
- **Tests:** включённый/выключенный visual feedback, отсутствие flash при failed retype и без `AppState`, persistence/clamping длительности.
- **Дальше:** расширенный floating mini-toast рядом с caret остаётся отдельной P3-идеей, потому что требует AX caret tracking и аккуратной transient-UI логики.
- **Effort:** done (простой) / 4 дня (расширенный).
- **Priority:** P0 (простой) / P3 (расширенный).

### 5.3. Текущая раскладка прямо в tray-иконке

- **Status:** DONE.
- Punto/Caramba: на иконке видны буквы текущей раскладки.
- **Реализовано:**
  1. `StatusItemController.updateLayoutBadge(_ languageCode:)` показывает двухбуквенный badge (EN/RU/UK/RO) в title.
  2. Подписка на смену input source через `InputSourceManager.onChange` в AppDelegate.
  3. `flashTrayIcon()` после flash вызывает `updateLayoutBadge` с текущей раскладкой, а не восстанавливает сохранённый title.
  4. Unit-тесты для `languageBadge` конвертации.
- **Tests:** `StatusItemControllerTests`.
- **Effort:** done.
- **Priority:** P1.

### 5.4. Smart Caps Lock

- **Status:** MISSING.
- Punto: одиночное нажатие CapsLock = переключить раскладку, двойное = настоящий Caps.
- Технически: захват CapsLock через CGEventTap, distinguished single vs double tap.
- **Этический момент:** ломает стандартное поведение системы, должно быть выключено по умолчанию.
- **Effort:** 2 дня.
- **Priority:** P2 (любители фанатеют, остальные ненавидят).

### 5.5. Global hotkey indicator

- **Status:** PARTIAL — есть HotkeysTab, но нет онлайн-обучения «вот сейчас сработал хоткей X».
- Caramba: показывает HUD при срабатывании любого хоткея. Хорошо для онбординга.
- **Effort:** 1 день.
- **Priority:** P3.

---

## 6. Per-app intelligence

### 6.1. App exclusions (blacklist)

- **Status:** DONE.
- `ExclusionList`.

### 6.2. Per-app rules (whitelist + поведение)

- **Status:** MISSING.
- Punto Pro: для каждого приложения — «авто», «только manual», «выкл», «только авто-замены».
- **План:** расширить ExclusionList в `AppRule { bundleID, mode: AppRuleMode }` где `AppRuleMode = .auto | .manualOnly | .disabled | .autoReplaceOnly`.
- **Effort:** 2 дня + тесты.
- **Priority:** P1.

### 6.3. Distinguishing field types (URL bar, password, code editor)

- **Status:** PARTIAL.
- Secure text — обрабатывается. Остальные роли (URL bar в Safari, code editor в Xcode) — нет.
- **План:** в `FocusedRoleProvider` добавить:
  - `kAXURLAttribute` присутствует → URL bar → отключить детектор.
  - `kAXRoleDescriptionAttribute == "address"` → отключить.
  - Для code-editor (Xcode source editor) — отдельная политика по запросу пользователя.
- **Effort:** 2 дня (AX-копание).
- **Priority:** P1.

### 6.4. Auto-detect input language by app context

- **Status:** MISSING.
- Punto-специфика: «когда фокус в Safari URL bar — всегда EN». Расширение P6.3.
- **Effort:** включено в P6.3.
- **Priority:** P1.

---

## 7. Расширение языков

### 7.1. Текущие пары

- **Status:** DONE — RU/EN, UK/EN, RO/EN.
- Важно: это список **поддержанных** пар, а не обещание, что все языки всегда участвуют в каждом решении детектора.

### 7.1.1. Active pairs как жёсткий фильтр кандидатов

- **Status:** DONE.
- **Реализовано:**
  1. `LanguagePair.uaEn` переименован в `ukEn`.
  2. `EnabledLanguagePairsStore` хранит пользовательски отключённые пары и по умолчанию включает только пары, реально обнаруженные через macOS input sources.
  3. Settings → Layouts показывает detected pairs с checkbox `Enabled`; отсутствующие пары показываются disabled с предупреждением.
  4. `TypingPipeline` передаёт текущие enabled pairs в `LayoutDetector`.
  5. `LayoutDetector` строит candidates только из текущей раскладки и target-языков включённых пар: RU→EN, RO→EN, UK→EN; при EN активны только non-EN стороны включённых пар.
  6. `SelectionTextConverter` использует только enabled pairs для convert-selection candidates.
- **Tests:** `EnabledLanguagePairsStoreTests`, active-pair regression tests в `LayoutDetectorTests`, `TypingPipelineTests`, `SelectionTextConverterTests`.
- **Effort:** done.
- **Priority:** P0/P1. Это снижает ложные конкуренции между EN/RO/RU/UK и делает поведение объяснимым: выключенный язык не может внезапно победить.

### 7.2. DE/EN, FR/EN, ES/EN, IT/EN

- **Status:** MISSING.
- Архитектура generic, добавление = новые `KeyboardMapping` + словари + n-грамм-модели.
- **Effort:** 3–4 дня на язык (не считая корпуса).
- **Priority:** P2 (по запросу).

### 7.3. Произвольные пары не-через-английский

- **Status:** MISSING.
- Punto в основном через EN. RU↔UK, например, не делает.
- **План:** обобщить `LanguagePair` и `LayoutDetector` чтобы детектировать любую неактивную из включённых.
- **Effort:** 5 дней (рефакторинг).
- **Priority:** P3.

---

## 8. Переплюнуть Punto / Caramba — то, чего у них нет

### 8.1. Полная локализация UI на 4 языках

- **Status:** DONE. Caramba — только RU и EN.

### 8.2. Корректная обработка румынских диакритик

- **Status:** DONE. Punto не делает.

### 8.3. Современный кодовый стек (Swift 6, Observation, Liquid Glass)

- **Status:** DONE. Punto/Caramba — Carbon legacy + старый AppKit.

### 8.4. Privacy section в Settings

- **Status:** DONE.
- Punto Яндекса передаёт телеметрию.
- **Реализовано:**
  1. Settings → General → Privacy & Security секция с 5 пунктами: Local-only processing, No network upload, Secure fields are skipped, Accessibility permission, Per-app control.
  2. HelpContent.privacy синхронизирован с пояснением Accessibility purpose, synthetic events, и per-app exclusions.
  3. Unit-тесты для HelpContent privacy section.
- **Tests:** `HelpContentTests`.
- **Effort:** done.
- **Priority:** P1.

### 8.5. Open architecture, plug-in dictionaries

- **Status:** PARTIAL — `BundledDictionaryLoader` грузит `.txt`-словари из bundle, `UserDictionary` умеет импортировать `.txt` через Settings → Dictionaries. Нет отдельного канала для plug-in corpus dictionaries и экспорта/импорта всего профиля.
- **План:** Settings → Dictionaries → импорт полноценного corpus `.txt` отдельно от UserDictionary, экспорт пользовательских словарей и тесты на формат.
- **Effort:** 1 день.
- **Priority:** P2.

### 8.6. Sparkle auto-update без App Store

- **Status:** MISSING.
- Punto/Caramba давно перестали обновляться. Если у нас будет Sparkle и регулярные релизы — это огромное преимущество.
- **План:**
  1. Интегрировать Sparkle 2.x.
  2. Поднять GitHub Releases с appcast.xml.
  3. Подписать релизы Developer ID + notarize.
- **Effort:** 3–4 дня (включая первую публикацию).
- **Priority:** P1, как только появится Developer ID.

### 8.7. CLI / scripting hook

- **Status:** MISSING.
- Возможность из shell скрипта переключить раскладку, запустить convert selection, опросить статус.
- **План:** mini CLI в `/usr/local/bin/layoutswitcher` (или helper скрипт), общающийся с приложением через `DistributedNotificationCenter` или Unix socket.
- **Effort:** 3 дня.
- **Priority:** P3.

### 8.8. Shortcuts (App Intents) integration

- **Status:** MISSING.
- Возможность вызвать «convert selection», «toggle» из системных Shortcuts. Современный аналог 8.7, более естественный для macOS Sequoia+.
- **План:** AppIntents-таргеты для основных действий.
- **Effort:** 2 дня.
- **Priority:** P1. Это «модно» и абсолютно недоступно конкурентам.

### 8.9. Spotlight / Quick Action для convert

- **Status:** MISSING.
- macOS Services: «выделить текст в любом приложении → правый клик → LayoutSwitcher → Convert layout».
- **План:** регистрация NSServices в Info.plist + SelectionConverter wrapper.
- **Effort:** 2 дня.
- **Priority:** P2.

### 8.10. Plain-text export всего пользовательского словаря и правил

- **Status:** PARTIAL (UserDictionary импортирует .txt).
- **План:** экспорт UserDictionary, AutoReplace rules, Exclusions в один `.layoutswitcher.json` для миграции между Mac.
- **Effort:** 1 день.
- **Priority:** P2.

### 8.11. iCloud sync настроек

- **Status:** MISSING.
- **План:** Sync UserDefaults через NSUbiquitousKeyValueStore + UserDictionary через CloudKit. Опционально.
- **Effort:** 4 дня.
- **Priority:** P3.

### 8.12. Voice feedback (accessibility)

- **Status:** MISSING.
- При авто-свитче — короткая подсказка через NSSpeechSynthesizer / AVSpeechSynthesizer.
- **Priority:** P3.

### 8.13. Open source

- **Status:** TBD.
- Если код будет на GitHub под MIT/Apache — это **гигантское** преимущество перед закрытыми Punto/Caramba.
- **План решения:** обсудить с пользователем модель распространения (open source vs proprietary freeware vs paid).

---

## 9. Дистрибуция и распространение

### 9.1. Ad-hoc signed zip

- **Status:** DONE — `scripts/release_zip.sh`.

### 9.2. Developer ID подписанная версия

- **Status:** MISSING.
- Требует Apple Developer Program ($99/год).
- Без неё: пользователь должен сам разрешить запуск через «Open Anyway» в System Settings → Privacy.
- **Effort:** 0.5 дня после получения сертификата.
- **Priority:** P0 если планируется публичный релиз.

### 9.3. Notarization

- **Status:** MISSING. Зависит от 9.2.
- **Effort:** 0.5 дня.
- **Priority:** P0 при публичном релизе.

### 9.4. DMG с custom background

- **Status:** MISSING.
- **Effort:** 1 день.
- **Priority:** P2.

### 9.5. Homebrew Cask

- **Status:** MISSING.
- **Effort:** 1 день после публичного релиза.
- **Priority:** P2.

### 9.6. Сайт-визитка

- **Status:** MISSING.
- Минимум: одностраничник со скриншотами, ссылкой на download, privacy policy.
- **Effort:** 2 дня (если делать самостоятельно на статичном генераторе).
- **Priority:** P1 при публичном релизе.

---

## 10. Quality moat — как выиграть не списком фич, а качеством

Parity с Punto/Caramba важен, но победа будет не в том, что у нас тоже есть автосвитч, хоткеи и автозамены. Победа — в предсказуемости: пользователь должен чувствовать, что приложение **никогда не портит текст**, быстро учится на отменах и даёт понятное объяснение, почему оно что-то сделало.

Публичные ориентиры на 2026-04-26:

- Официальная страница Punto подчёркивает автоопределение раскладки, горячие клавиши и автозамены: <https://yandex.ru/soft/punto/mac/>
- Страница Caramba в App Store показывает, что продукт живой, платный по подписке, RU/EN, macOS 11.5+; в отзывах заметны боли вокруг Enter, исключений и недостаточной конфигурируемости: <https://apps.apple.com/us/app/caramba-switcher/id1565826179?mt=12>
- Это подтверждает стратегию: не просто догонять, а делать **trust-first switcher** — безопасный, объяснимый, локальный и измеримый.

### 10.1. Golden Corpus / Decision Lab

- **Status:** MISSING.
- Нужен локальный набор тест-кейсов, который измеряет качество детектора не только unit-тестами, а как продуктовую метрику.
- Примеры групп:
  - RU/EN wrong-layout: `ghbdtn`, `vfvf`, `rfr`, `ltkf`.
  - EN/RU: `руддщ`, `пщщв`, `цщкдв`.
  - EN/RO collisions: `hello`, `salut`, `mama`, `casa`, `buna`.
  - RU/UA collisions: `привет`, `привіт`, `мама`, `слово`.
  - URL/email/code: `https://`, `user@gmail.com`, `git@github.com`, `UIViewController`.
  - Messenger flows: word + space, word + Enter, word + punctuation.
- **План:**
  1. Создать `LayoutDetectorCorpusTests`.
  2. Хранить fixtures в JSON/YAML: active language, keycodes/text, expected decision, expected target.
  3. Считать confusion matrix: false switch, missed switch, wrong target language.
  4. Добавить CLI/script `scripts/detector_corpus_report.swift` или тестовый helper, который печатает markdown-таблицу.
- **Effort:** 2–3 дня.
- **Priority:** P0. Это даёт нам инженерный рычаг качества, которого обычно нет у legacy-конкурентов.

### 10.2. Shadow Mode перед включением автоперепечати

- **Status:** MISSING.
- Режим «наблюдать, но не исправлять»: детектор принимает решения, пишет безопасные counters/reason codes, но не стирает текст.
- Пользователь может включить Shadow Mode на день и увидеть:
  - сколько было бы авто-свитчей;
  - сколько решений были ambiguous;
  - какие приложения чаще всего рискованные;
  - сколько раз сработали URL/email/code guards.
- Важно: не логировать сам текст. Для диагностики можно хранить только категорию решения, язык, длину слова, bundleID и reason code.
- **Effort:** 2 дня.
- **Priority:** P0 для публичного релиза. Это снижает страх перед приложением, которому нужно Accessibility permission.

### 10.3. Explainable Corrections

- **Status:** MISSING.
- В Recent auto-switches добавить раскрываемую строку «Why?»:
  - active language;
  - target language;
  - dictionary hits;
  - ngram delta;
  - NL probability, если участвовала;
  - rule/guard, если свитч был подавлен.
- Рядом действия:
  - `Always keep this word`;
  - `Always switch this word`;
  - `Exclude this app`;
  - `Report bad switch` (локальный diagnostic bundle).
- **Effort:** 2–3 дня.
- **Priority:** P1. Это превращает чёрный ящик в обучаемый инструмент и резко повышает доверие.

### 10.4. Retype Transaction Safety Score

- **Status:** PARTIAL.
- Уже есть важная часть transaction gate: `Retyper` делает preflight до любого destructive действия — target layout resolution, RO→EN fallback, pre-encoding всех символов, выбор и подтверждение target layout. Stats/recents/lastAutoSwitch пишутся только после `retypeResult.succeeded`.
- Нужен явный safety score поверх уже существующего preflight.
- Перед erase/retype считать safety score:
  - focused app bundleID тот же;
  - focused element не secure;
  - нет mouse click / focus change после commit;
  - target layout доступен;
  - target layout подтвердился;
  - длина операции в пределах лимита;
  - приложение не в manual-only / disabled mode.
- Если score ниже порога — не стирать, а показать `lastActionDescription = "Switch skipped: unsafe focus state"`.
- **Effort:** 2 дня.
- **Priority:** P0/P1. Главный принцип: лучше пропустить исправление, чем испортить чужой текст.

### 10.5. Local Personal Language Model

- **Status:** MISSING.
- Сейчас есть UserDictionary и будущий Negative Learning. Следующий уровень — локальный профиль пользователя:
  - слова, которые пользователь часто оставляет;
  - слова, которые пользователь часто вручную переключает;
  - app-specific preference: Slack может быть RU-heavy, Xcode EN-heavy.
- **План:**
  1. `PersonalLanguageProfile` с TTL и per-bundle статистикой.
  2. Обновлять только на явных действиях: undo, force-retype, manual convert, добавление в dictionary.
  3. Использовать как маленький bias в tie-break, но не как единственный сигнал.
  4. UI: «Reset learning».
- **Effort:** 4–5 дней.
- **Priority:** P1. Это то, что делает продукт лучше именно у конкретного пользователя, а не только на нашем corpus.

### 10.6. App Compatibility Matrix

- **Status:** MISSING.
- Конкурентное качество на macOS — это не только алгоритм, а совместимость с реальными приложениями.
- Матрица:
  - Native: TextEdit, Notes, Mail, Safari.
  - Chromium/Electron: Chrome, Edge, Slack, Discord, VS Code.
  - Messengers: Telegram, WhatsApp, Signal.
  - IDE/terminals: Xcode, Terminal, iTerm2, JetBrains.
  - Secure/password: 1Password, Bitwarden, Keychain Access.
- Для каждого приложения фиксировать:
  - AX selected text read/write;
  - clipboard fallback;
  - caret range availability;
  - focus-change behaviour;
  - recommended default mode (`auto`, `manualOnly`, `disabled`).
- **Effort:** 2 дня на первую таблицу + постоянное обновление.
- **Priority:** P1. Это позволит говорить «работает в Slack/Telegram/Chrome» не на ощущениях, а по проверке.

### 10.7. Diagnostics Without Keylogging

- **Status:** MISSING.
- Нужен экспорт диагностики для bug reports, который не содержит набранного текста.
- Содержимое:
  - app version, macOS version, enabled layouts;
  - permissions status;
  - recent reason codes без raw text;
  - failed retype reasons;
  - exclusion/app-rule snapshot;
  - detector thresholds.
- Опционально: пользователь может вручную приложить конкретный problematic word, но это явное действие.
- **Effort:** 1.5 дня.
- **Priority:** P1. Это поддержка уровня «можно чинить баги», не превращая приложение в keylogger.

### 10.8. Automatic Safety Downgrade

- **Status:** MISSING.
- Если в конкретном приложении за короткое время случились repeated failures:
  - layout confirmation timeout;
  - focus mismatch;
  - rollback;
  - user immediately undid multiple switches;
то приложение автоматически переводится в `manualOnly` на 24 часа с уведомлением.
- **Effort:** 2 дня поверх Per-app rules.
- **Priority:** P1. Это защитит от самых неприятных сценариев: «приложение внезапно начало портить текст в одном конкретном чате/IDE».

### 10.9. Confidence UI для спорных кейсов

- **Status:** MISSING.
- Для низкой уверенности не делать авто-свитч, а подсветить tray/показать unobtrusive suggestion:
  - «Maybe EN? Press hotkey to convert last word».
- Это режим между `keep` и `switchAndRetype`.
- **Effort:** 3 дня (нужен UX, чтобы не раздражать).
- **Priority:** P2. Полезно для новых языков и спорных EN/RO/RU/UA коллизий.

### 10.10. Rule Packs / Presets

- **Status:** MISSING.
- Вместо одного набора дефолтов — пресеты:
  - `Safe`: меньше авто-свитчей, больше manual suggestions.
  - `Balanced`: текущий дефолт.
  - `Aggressive`: для пользователей Punto, которые хотят максимум автоматики.
  - `Developer`: auto disabled in terminals/IDEs, URL/code guards stronger.
  - `Messenger`: Enter-safe, punctuation-friendly, toast/sound on.
- **Effort:** 1 день после реализации per-app rules и guards.
- **Priority:** P1/P2. Это дешевле, чем 30 отдельных toggles, и лучше для онбординга.

### 10.11. First-run Interactive Calibration

- **Status:** MISSING.
- В onboarding дать 6–8 коротких упражнений:
  - набрать `ghbdtn`;
  - исправить выделение;
  - undo;
  - добавить слово в dictionary;
  - выбрать safe/aggressive preset.
- По результатам выставить sensitivity/preset.
- **Effort:** 2–3 дня.
- **Priority:** P2. Это снижает порог входа и делает продукт «понятным» с первых минут.

### 10.12. Public Quality Changelog

- **Status:** MISSING.
- Не просто changelog «fixed bugs», а метрики:
  - corpus cases: 240 → 310;
  - false switches: 4 → 2;
  - new app compatibility: Slack, Telegram;
  - new guards: URL/email/code.
- **Effort:** 0.5 дня на процесс.
- **Priority:** P2. Это усиливает доверие и показывает, что продукт живее legacy-конкурентов.

---

## 11. Дополнения после ревью — корректность и реальные UX-пробелы

Раздел добавлен после повторного аудита на 2026-04-27. Это пункты, которые не вошли в первоначальный план и которые имеют реальное обоснование — не «чтобы было».

### 11.1. Dead-key / композиционный ввод (Romanian, German, French)

- **Status:** MISSING.
- Румынская стандартная раскладка использует мёртвые клавиши для `ă/â/î/ș/ț`. Французские/немецкие раскладки — для `é/à/ñ/ü`. Сейчас наш `WordBuffer` собирает поток событий **до** того, как система применит композицию, и может неправильно определить word boundary или отдать в детектор «сырой» поток без скомпонованного символа.
- **План:**
  1. Аудит обработки `kCGEventFlagMaskNonCoalesced` и взаимодействия с TSM (Text Services Manager).
  2. Детектировать composing-state и не трогать буфер до завершения композиции.
  3. Регрессионные тесты на ввод диакритик через dead-keys в `Romanian — Standard`.
- **Effort:** 2–3 дня.
- **Priority:** P0 для корректности — мы заявляем поддержку Romanian, должна работать.

### 11.2. IME passthrough (Chinese / Japanese / Korean / Phonetic Russian)

- **Status:** MISSING.
- При активном IME CGEventTap видит сырые латинские нажатия, но реальный итоговый текст генерируется IME отдельно. Наш пайплайн считает это английским вводом и может попытаться «исправить» валидный pinyin / romaji.
- **План:** при `TISInputSource.kTISPropertyInputSourceCategory == kTISCategoryKeyboardInputMethod` (а не `kTISCategoryKeyboardInputSource`) — отключать детектор полностью до выхода из IME. Логировать переход.
- **Effort:** 1–2 дня.
- **Priority:** P0. Без этого приложение гарантированно ломает ввод у пользователей с CJK / phonetic IME.

### 11.3. Auto-launch on login через SMAppService

- **Status:** MISSING.
- Сейчас пользователь должен вручную запускать приложение после каждой перезагрузки. Для menu-bar утилиты это критическая дыра ожидания.
- **План:** Settings → General → toggle «Launch at login». Реализация через `SMAppService.mainApp.register()` (macOS 13+), без legacy login items / launchd plist.
- **Effort:** 0.5 дня.
- **Priority:** P0.

### 11.4. Аудит работы с несколькими input sources на один язык

- **Status:** PARTIAL.
- `LanguageID(inputSourceLanguageCode:)` берёт 2-буквенный prefix, что в большинстве случаев корректно, но `KeyboardMapping` тестирован только на одной конкретной раскладке для каждого языка. Реальные пользователи имеют 2–4 источника на язык: `ABC`, `ABC Extended`, `U.S.`, `Russian — PC`, `Russian — Phonetic`, `Ukrainian — PC` и т.д.
- **План:**
  1. Прогнать regression-набор по всем популярным input sources для RU/UK/RO/EN.
  2. Зафиксировать матрицу «source → корректность mapping».
  3. Где есть расхождения — подгружать `keyCode → character` динамически через `UCKeyTranslate` поверх `kTISPropertyUnicodeKeyLayoutData` активного источника.
- **Effort:** 2 дня (аудит) + 1–2 дня (правка mapping, если нужна).
- **Priority:** P1.

### 11.5. Wake-from-sleep + hot-plug re-detection input sources

- **Status:** PARTIAL.
- `InputSourceManager` слушает TIS-нотификации, но при wake-from-sleep или подключении Bluetooth-клавиатуры эти нотификации могут не приходить вовремя, и мы будем работать со stale state.
- **План:**
  1. Аудит существующих TIS-наблюдателей на wake-сценарии.
  2. Подписка на `NSWorkspace.didWakeNotification` и IOKit device-notifications для USB/Bluetooth keyboards.
  3. Принудительно вызывать refresh при пробуждении.
- **Effort:** 1 день (аудит) + 1 день (правка).
- **Priority:** P1.

### 11.6. Snooze / Pause hotkey

- **Status:** DONE.
- У нас есть только глобальный on/off, который пользователь забывает обратно включить. Реальный кейс: набираю команду в терминале / диктую вслух / копирую код — нужен временный mute на 5/15/60 минут с авто-возвратом.
- **Реализовано после recovery-аудита:**
  1. Новый `HotkeyAction.snooze`.
  2. Default binding: `⌃⌥⌘P`.
  3. `AppState` хранит runtime `snoozedUntil` и persisted duration 5/15/60 минут.
  4. Во время snooze pipeline продолжает коммитить слова и поддерживает ручные хоткеи, но подавляет automatic retype.
  5. Menu bar показывает `P<minutes>` countdown badge; меню даёт `Snooze` / `Resume`.
  6. Settings → General содержит выбор длительности snooze.
  7. `HelpContent` описывает Snooze в hotkeys и Preferences.
- **Tests:** `AppStateTests.snoozeDurationPersistsAndClamps`, `AppStateTests.activeSnoozeRemainingClearsExpiredPause`, `HotkeyRegistryTests.defaultBindingsIncludeSnooze`, `HotkeyCoordinatorTests.snoozeHotkeyStartsConfiguredPause`, `HotkeyCoordinatorTests.snoozeHotkeyClearsActivePause`, `TypingPipelineTests.snoozeCommitsWordsButSuppressesAutoSwitch`, `TypingPipelineTests.expiredSnoozeAllowsAutoSwitchAgain`, `TypingPipelineTests.snoozeStartedBeforeDelayedEvaluationSuppressesPendingWord`, `StatusItemControllerTests`.
- **Effort:** done.
- **Priority:** P1.

### 11.7. Multi-word sequence retype

- **Status:** DONE.
- Реализован conservative MVP для burst-коррекций 2–3 слов подряд одним retype-блоком.
- **Реализовано:**
  1. Sliding window в `TypingPipeline` хранит до 3 совместимых `switchAndRetype` candidates.
  2. Internal separators в блоке: только Space (`previous.word.separator == .space`).
  3. Final separator: Space или punctuation (Enter/Tab исключены из auto-switch path).
  4. Sequence boundary: short lookahead `120ms` на старт следующего слова, long pause `2.0s` между committed words внутри sequence считается по `CommittedWord.committedAt`; focus change, mouse click, navigation, escape, secure field, app disabled, modifier shortcut, technical boundary, digit poison сбрасывают context.
  5. Multi-word retype выполняется через `Retyper.retypeSequenceResult(...)` с preflight-энкодингом всего блока и safe punctuation restore через Unicode.
  6. Один `AutoSwitchRecord` на весь блок; undo использует `originalText` + `retypeSequenceResult` и откатывает block одним действием.
  7. Один stats/recent/cooldown entry для whole block; при failed retype запись side-effects не происходит.
  8. Unsafe boundary после pending word сбрасывает sequence без destructive fallback, чтобы не делать backspace из уже изменившейся позиции курсора.
- **Tests:** `TypingPipelineTests.twoWrongLayoutWordsAreRetypedAsSingleBlock`, `TypingPipelineTests.threeWrongLayoutWordsAreRetypedAsSingleBlock`, `TypingPipelineTests.multiWordBlockWithPunctuationRestoresFinalSeparatorAsUnicode`, `TypingPipelineTests.focusChangeResetsPendingMultiWordSequence`, `TypingPipelineTests.failedMultiWordRetypeDoesNotRecordStatsOrRecents`, `TypingPipelineTests.repeatedIdenticalMultiWordBlockIsSuppressedDuringCooldown`, `TypingPipelineTests.multiWordCooldownDoesNotSuppressSameLastWordWithDifferentPreviousContext`, `RetyperTests.sequenceRetypeEncodesInternalSpacesAsKeyEvents`, `RetyperTests.sequenceRetypeRestoresFinalPunctuationAsUnicode`.
- **Effort:** done.
- **Priority:** P1.

### 11.8. Convert last N words hotkey

- **Status:** MISSING after recovery audit.
- Расширение `forceRetypeLastWord` (1.6): хоткей конвертирует последний безопасный блок committed words без выделения текста.
- **Не восстановлено в текущем коде:** `HotkeyAction.forceRetypeLastWords`, rolling history в `WordBuffer`, hotkey binding и tests.
- **План:**
  1. Новый `HotkeyAction.forceRetypeLastWords`.
  2. Default binding: `⌃⌥⌘\`.
  3. `WordBuffer` хранит rolling history последних 3 `CommittedWord`.
  4. `HotkeyCoordinator` берёт latest safe suffix: max 3 words, same bundle, 3-second window, internal separators only Space, final separator Space/punctuation.
  5. Technical tokens и открытое текущее слово не конвертируются.
  6. Retype выполняется одним `Retyper.retypeSequenceResult(...)`; stats/recents пишутся одной manual entry только после success.
- **Tests planned:** `HotkeyRegistryTests.defaultBindingsIncludeForceRetypeLastWords`, `HotkeyCoordinatorTests.forceRetypeLastWordsRetypesLatestThreeCommittedWords`, `HotkeyCoordinatorTests.forceRetypeLastWordsStopsAtUnsafeInternalSeparator`, `HotkeyCoordinatorTests.forceRetypeLastWordsSkipsTechnicalLastToken`, `HotkeyCoordinatorTests.forceRetypeLastWordsSkipsWhenCurrentWordIsOpen`, `HotkeyCoordinatorTests.forceRetypeLastWordsUsesBundleAwareSuffix`, `WordBufferTests.recentCommittedWordsKeepsLatestThreeWords`, `WordBufferTests.resetClearsRecentCommittedWords`, `WordBufferTests.backspaceAfterSeparatorClearsRecentCommittedWords`.
- **Effort:** ~1 day.
- **Priority:** P2.

### 11.9. Presentation mode

- **Status:** PARTIAL after recovery audit.
- При screen sharing (Zoom / Meet / Teams в фокусе / `kCGSessionShare`), Keynote в presentation mode или включённом Do Not Disturb — автоматически переходить в `manualOnly`. Иначе зрители на демо видят, как слова сами стираются и перепечатываются — выглядит как баг.
- **Восстановлено:** `PresentationModeDetector` и unit tests на detector.
- **Не восстановлено/не интегрировано:** `AppState` setting, suppression в `TypingPipeline`, badge/status menu и Settings UI.
- **План:**
  1. `PresentationModeDetector` с сигналами:
     - known focused meeting/presentation apps: Zoom, Teams, Webex, Keynote, PowerPoint;
     - `CGSessionCopyCurrentDictionary()` sharing-like truthy flags, включая `kCGSessionShare`-style ключи;
     - `INFocusStatusCenter.default.focusStatus.isFocused`, если macOS раскрывает Focus status приложению.
  2. `TypingPipeline` переводит auto-switch в manual-only: words продолжают коммититься, manual hotkeys работают, automatic retype suppress.
  3. Settings → General: toggle `Pause automatic switching during presentation mode`.
  4. Menu bar: badge `PR` и disabled status item с причиной.
  5. `HelpContent` и parity docs обновлены.
- **Tests:** `PresentationModeDetectorTests.knownMeetingBundleActivatesPresentationMode`, `PresentationModeDetectorTests.sessionSharingFlagActivatesPresentationMode`, `PresentationModeDetectorTests.focusStatusActivatesPresentationMode`, `PresentationModeDetectorTests.ordinaryContextStaysInactive`.
- **Tests planned:** `TypingPipelineTests.presentationModeCommitsWordsButSuppressesAutoSwitch`, `TypingPipelineTests.disabledPresentationModeSettingAllowsAutoSwitch`, `AppStateTests.presentationModeAutoPauseSettingPersistsAcrossInstances`, `StatusItemControllerTests.presentationModeBadgeIsCompact`.
- **MVP-limit:** browser Meet tab detection зависит от системного/window/session сигнала; без stable public tab/title signal весь Chrome/Safari не переводится в manual-only.
- **Effort:** ~1 day.
- **Priority:** P2.

### 11.10. Click on tray icon — toggle layout (опция)

- **Status:** MISSING after recovery audit.
- Punto: левый клик по иконке = переключить раскладку, правый клик = меню. У нас оба клика открывают меню.
- **Не восстановлено в текущем коде:** `TrayClickAction`, persisted setting и manual click routing. Сейчас status item показывает layout badge и обычное меню.
- **План:**
  1. `TrayClickAction`: `Show menu`, `Toggle layout`, `Show recent`; default `Show menu`, чтобы сохранить старое поведение.
  2. Settings → General → `Tray icon click`.
  3. Status item обрабатывает clicks вручную: right-click / Control-click всегда открывает full menu.
  4. `Toggle layout` выбирает противоположную поддерживаемую раскладку: non-English → English, English → последняя non-English или первая доступная RU/UK/RO.
  5. `Show recent` открывает компактное меню recent switches.
- **Tests planned:** `AppStateTests.trayClickActionPersistsAcrossInstances`, `StatusItemControllerTests.nextLayoutTogglesNonEnglishToEnglish`, `StatusItemControllerTests.nextLayoutTogglesEnglishToPreferredNonEnglish`, `StatusItemControllerTests.nextLayoutIgnoresDisabledAndUnselectableLayouts`, `StatusItemControllerTests.nextLayoutCyclesWhenLanguagePairIsUnsupported`.
- **Effort:** ~0.5 day.
- **Priority:** P2.

### 11.11. Drag-and-drop импорт в редактор словаря

- **Status:** PARTIAL after recovery audit.
- Сейчас только через NSOpenPanel. macOS-native — drop `.txt` файла прямо на список слов в `DictionaryEditor`.
- **Восстановлено:** import через `NSOpenPanel` и `UserDictionary.importFromText(_:)`.
- **Не восстановлено:** drag-and-drop target, file URL import helper, drag highlight.
- **Tests planned:** `DictionaryTests.userDictionaryImportFromTextReturnsInsertedCountAndNormalizes`, `DictionaryTests.userDictionaryImportsPlainTextFile`, `DictionaryTests.userDictionaryRejectsUnsupportedImportFileType`.
- **Effort:** ~0.5 day.
- **Priority:** P3 (полировка, но дёшево).

### 11.12. Audit log (метаданные без контента)

- **Status:** MISSING after recovery audit.
- Требуется приватный `AuditLog`: timestamp, action, outcome, reason code, bundleID, language transition, token length, token count, separator type.
- Журнал не хранит raw text: ни original, ни corrected, ни selected text.
- Покрытые события MVP:
  - automatic switch success/failure/suppression;
  - manual retype success/failure/suppression;
  - undo success/failure/suppression;
  - selection conversion success/suppression;
  - snooze start/clear.
- В Settings нужна вкладка Audit с просмотром, очисткой и JSON export.
- **Tests:**
  - `AuditLogTests.recordKeepsMetadataOnlyAndTrimsToCapacity`;
  - `TypingPipelineTests.successfulAutoSwitchRecordsMetadataOnlyAuditEntry`;
  - `TypingPipelineTests.failedAutoSwitchRecordsMetadataOnlyAuditEntry`;
  - `HotkeyCoordinatorTests.successfulManualRetypeRecordsMetadataOnlyAuditEntry`;
  - `HotkeyCoordinatorTests.successfulUndoRecordsMetadataOnlyAuditEntry`.
- **Priority:** P2.

### 11.13. Per-pair sensitivity (вместо глобальной)

- **Status:** MISSING.
- Сейчас `DetectionSensitivity` глобальная. Реальный кейс: пользователь хочет агрессивный детектор для RU/EN, но осторожный для UK/EN (редкие false positives на украинских заимствованиях).
- **План:** `Map<LanguagePair, DetectionSensitivity>` вместо одного значения. UI: per-pair pickers в Layouts tab.
- **Effort:** 1 день.
- **Priority:** P2.

### 11.14. System Dictation event filter

- **Status:** MISSING.
- Apple Dictation генерирует синтетические события, которые не помечены нашим `SyntheticEventFilter`-тегом. Если пользователь диктует — события выглядят как реальный ввод.
- **План:** при активном dictation (`AVSpeechSynthesizer` / TIS dictation source detection) — приостанавливать пайплайн.
- **Effort:** 1 день.
- **Priority:** P2.

---

## Что не предлагается и почему

Зафиксировано, чтобы не возвращаться:

- **Plugin API / extensibility** — рано, нет внешних потребителей.
- **Browser extension** — CGEventTap уже видит ввод в браузере, отдельный extension избыточен.
- **Regex auto-replace** — на 90% не нужен реальным пользователям, резко увеличивает площадь багов.
- **Облачный E2E sync** — iCloud (8.11) покрывает; свой канал не имеет смысла.
- **iOS-версия** — нет CGEventTap-аналога на iOS, технически невозможно сделать аналог.
- **Большая CoreML-модель для детекта** — наш NL-скорер уже даёт 95%+; вкладываться ради ещё 1–2% точности не окупится по размеру bundle и сложности обновления.

---

## Итоговая последовательность реализации

### Спринт 0 — Quality foundation

Перед дальнейшим наращиванием фич стоит заложить измеримость, безопасность и корректность. Иначе AutoReplace/Diary/AppRules увеличат площадь багов быстрее, чем мы сможем их контролировать.

**Качество:**

- 10.1 — Golden Corpus / Decision Lab (P0)
- 10.2 — Shadow Mode (P0)
- 10.4 — Retype Transaction Safety Score (P0/P1)
- 10.7 — Diagnostics Without Keylogging (P1)

**Корректность (из раздела 11):**

- 7.1.1 — Active pairs как жёсткий фильтр кандидатов (P0/P1)
- 11.1 — Dead-key / композиционный ввод (P0)
- 11.2 — IME passthrough (P0)
- 11.3 — Auto-launch on login через SMAppService (P0)

**Итого:** ~13–14 дней.

### Спринт 1 — UX-quick-wins + obvious gaps

Закрывает то, что **дёшево** и сразу заметно пользователю.

- 1.5 — Negative learning после ⌘Z (P0) — DONE
- 1.6 — Force-retype last word хоткей (P0) — DONE
- 1.8 — URL/email guard (P0) — DONE
- 5.1 — Звук при авто-свитче (P0) — DONE
- 5.2 — Visual flash на tray-иконке (P0, простой вариант) — DONE

**Осталось:** закрыто.  
**Итого осталось:** 0 дней.

### Спринт 2 — Распространение + критическая UX

- 9.2 — Developer ID + 9.3 Notarization (P0)
- 8.6 — Sparkle (P1)
- 5.3 — Tray icon с буквами раскладки (P1) — DONE
- 8.4 — Privacy section в Settings (P1) — DONE

**Итого:** ~6 дней.

### Спринт 3 — Per-app intelligence + cooldown

- 1.7 — Cooldown повторного авто-свитча (P1) — DONE
- 6.2 — Per-app rules (P1)
- 6.3 — Field type detection (URL bar etc.) (P1)
- 1.10 — Аудит цифрового ряда / пунктуации (P1)
- 11.4 — Multi input source per language audit (P1)
- 11.5 — Wake / hot-plug re-detection (P1)
- 11.6 — Snooze / Pause hotkey (P1) — DONE

**Итого:** ~9.5 дней.

### Спринт 4 — Selection power tools

- 2.2 — Smart Capitalization (P1)
- 8.8 — App Intents / Shortcuts (P1)
- 2.3 — Транслитерация (P2)

**Итого:** ~7 дней.

### Спринт 5 — Auto-replace

- 3.1 — Auto-replace rules + UI (P1)
- 3.2 — Динамические подстановки (P2)

**Итого:** ~9 дней.

### Спринт 6 — Кардинальная фича

- 1.2 — In-line cursor word detection (P1)
- 11.7 — Multi-word sequence retype (P1) — DONE
- 4.1 — Optional encrypted Diary (P2, по запросу)

**Итого:** ~14 дней.

### Бэклог (P2/P3)

- Дополнительные языки (DE/FR/ES/IT)
- Smart Caps Lock
- Транслит / Reverse case / нормализация
- iCloud sync
- CLI hook
- Spotlight Services
- Voice feedback
- 11.8 — Convert last N words hotkey
- 11.9 — Presentation mode — PARTIAL
- 11.10 — Tray click toggle
- 11.11 — Drag-and-drop dictionary import — PARTIAL
- 11.12 — Audit log (метаданные без контента)
- 11.13 — Per-pair sensitivity
- 11.14 — System Dictation event filter
- Sparkle auto-update — поднять до P0 если будет паблик-релиз

---

## Итог: чего не хватает «на сегодня», чтобы переплюнуть Punto / Caramba

Для **корректности и функциональной паритетности**: спринты 0–3 (~32 дня с учётом уже закрытых 1.5, 1.6 и 5.1). Спринт 0 здесь обязателен — без dead-key / IME passthrough / launch at login называть приложение продакшеном нельзя.

Для **превосходства**: спринты 0–5 + современная подача (+ публикация со Sparkle, документация, open source) — ~60 дней работы. На выходе получаем продукт, у которого:

- **есть всё, что есть у Punto/Caramba**, кроме узких legacy-фич типа Diary (которую мы можем сделать опционально с шифрованием — лучше, чем у Punto);
- **есть то, чего у них нет**: румынские диакритики, EN/RU/RO/UK UI, App Intents, Sparkle, privacy-by-design, современный стек, IME-aware пайплайн, multi-word sequence retype, presentation mode, измеримое качество через Golden Corpus;
- **актуален на macOS Sequoia/Tahoe**, тогда как Punto и Caramba регулярно ломаются на новых версиях.

Это реалистичный план одного разработчика на 3–4 месяца фокусированной работы.
