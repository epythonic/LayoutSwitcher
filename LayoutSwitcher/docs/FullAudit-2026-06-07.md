# LayoutSwitcher — Полный аудит

**Дата:** 2026-06-07
**Версия кода:** ветка `main` @ `ed7b01b` + незакоммиченное рабочее дерево (8 файлов, +378/−50)
**Метод:** статический аудит по коду. Сборка/тесты в рамках аудита не запускались (см. «Проверка»). Ведущая тема — корректность и разрастание логики коррекции.

Отметки: ✅ — проверено построчно по коду; ⚠️ — по карте кодбейза (Explore), требует подтверждения при работе.
Severity: **HIGH** (бьёт по корректности/сопровождаемости и активно растёт) · **MED** (реальный риск/долг) · **LOW** (полировка) · **INFO** (корректно, зафиксировано).

---

## 1. Резюме

LayoutSwitcher — зрелое приложение: чистая Swift 6 / `@MainActor`-изоляция, DI системных эффектов, безопасный двухфазный retype (префлайт без разрушающих действий → деструктивная фаза), высокий коэффициент тестов (49 тест-файлов на 87 файлов кода, ~11 900 стр. кода приложения), отсутствие внешних зависимостей, корректная для CGEventTap конфигурация (sandbox off, hardened runtime on, input-monitoring entitlement).

Главная проблема — **не отдельные баги, а эрозия архитектуры в зоне принятия решения о коррекции**. Логика решения размазана между `LayoutDetector` и `TypingPipeline`, дублируется, обрастает спец-кейсами под конкретные слова и языки. Это подтверждается историей: последние 5 коммитов — сплошь `fix:` вокруг этой зоны, а незакоммиченный диф добавляет +133 строки в `TypingPipeline` (почти все — новые ветки) и хардкод русских слов. Это классический whack-a-mole: каждый фикс рискует регрессировать соседний сценарий.

### Сводная таблица

| # | Severity | Находка | Файл |
|---|----------|---------|------|
| 1.1 | **HIGH** | Whack-a-mole: решение о коррекции размазано/дублировано между детектором и пайплайном | `TypingPipeline.swift` |
| 1.2 | **HIGH** | Хардкод исправлений под конкретные слова (`заключил`) в исходнике + словаре + тестах | `SpellingSuggestionProvider.swift` |
| 4.1 | **HIGH** | `MACOSX_DEPLOYMENT_TARGET = 15.7` отсекает 15.0–15.6 | `project.pbxproj` |
| 1.3 | MED | Дублирующие точки входа `decide()` vs `decideVisibleTextCorrection()` | `LayoutDetector.swift` |
| 1.4 | MED | `shouldKeepNonConvertibleRaw` — ещё один полный ре-рендер всех языков | `LayoutDetector.swift` |
| 2.1 | MED | Детекция (вкл. `NSSpellChecker`) синхронно на main thread в callback tap; `guesses()` без кэша | `KeyboardEventTap`/`SystemSpellChecker` |
| 5.1 | MED | Тесты «зелёные по построению» из-за хардкод-слов | `TypingPipelineTests.swift` |
| 2.2 | LOW | `waitForLayout` — фикс. таймаут 200 мс + busy-poll | `Retyper.swift` |
| 3.1 | LOW | `charsToErase = original.count + 1` — неявный инвариант «1 нажатие = 1 символ» | `Retyper.swift` |
| 4.2 | LOW | subsystem логгера `GIH.LayoutSwitcher` ≠ bundle id `GM.LayoutSwitcher` | весь код |
| 1.5 | LOW | Непоследовательный ключ микрокэша `\(lang)\u{0}\(text)` | `LayoutDetector.swift` |
| 5.2 | LOW | Реальные `sleep` в тестах снижают детерминизм | тесты |
| 6.* | LOW | Документация: `nonfunctionsl.txt` (опечатка), `Swift6CodeQualityAudit.md` 427 КБ, дрейф Roadmap↔код | `docs/` |

---

## 2. Корректность и разрастание логики коррекции (ведущий раздел)

### 1.1 [HIGH] ✅ Whack-a-mole в принятии решения о коррекции

В идеале весь анализ слова делает чистый `LayoutDetector.decide()`. Фактически `TypingPipeline` строит собственное решение поверх детектора и **повторно рендерит буфер во всех языках и заново опрашивает словари**.

Цепочка веток в `preferredCrossLayoutDecisionBeforeVisibleCorrection` (`LayoutSwitcher/Pipeline/TypingPipeline.swift:310-396`) — последовательность из ~6 эвристик, каждая под свой сценарий:
- `pendingSequenceContextDecision` (`:398-427`)
- `recentAutoSwitchContextDecision` (`:429-441`) + `recentAutoSwitchContextTarget` (`:443-459`) + `recentMatchesPreviousWord` (`:461-467`) + `preferredCorrectionLanguage` (`:469-478`)
- `shouldVisibleLatinOutrankRenderedCorrection` (`:526-536`) + `isKnownVisibleLatinWord` (`:538-543`)
- два цикла `renderedContextDecision`-стиля прямо в теле (`:362-391`)

Плюс отдельный хардкод-язык в `evaluate`:

```swift
// TypingPipeline.swift:236-246
for renderedLanguage in sameLanguageCorrectionCandidates(activeLanguage: activeLanguage) {
    guard renderedLanguage == .ru else { continue }   // ← русский прибит гвоздём
    ...
    if applyRenderedRussianYoCorrection(text: renderedText, word: word) { return }
}
```

**Места повторного render+dict** (то, что уже умеет `decide()`): `:238`, `:294`, `:300-301`, `:359`, `:366`, `:382-386`, `:409`, `:418`, `:481`, `:488`. Источника истины для решения нет — он расщеплён между `LayoutDetector.decide`, `LayoutDetector.decideVisibleTextCorrection` и пятью-шестью хелперами пайплайна.

**Доказательство разрастания:** коммиты `ed7b01b` «keep visible Russian words over stale English render», `b1d9c17` «trust validated Russian typo suggestions», `08f9b79`, `6f92174` «make typo correction language-aware and robust» — все вокруг этой зоны; диф рабочего дерева добавляет в `TypingPipeline` `pendingSequenceContextDecision`, `recentAutoSwitchContextDecision`, `renderedContextDecision`, `preferredCorrectionLanguage`, `isCorrectionLanguageEnabled` — +133 стр.

**Риск:** хрупкий порядок веток; каждый новый сценарий рискует сломать предыдущий; крайне высокая стоимость сопровождения; поведение трудно предсказать по коду.

**Рекомендация:** ввести единую функцию решения в детекторе, принимающую контекст: `decide(buffer:, visibleText:, activeLanguage:, context: DecisionContext)`, где `DecisionContext` несёт `pendingSequenceTarget`, `recentAutoSwitchTarget`, `enabledTargets`, флаги фич. Детектор возвращает одно решение; пайплайн только оркестрирует ввод/вывод и не повторяет детекцию. Зафиксировать модель приоритетов (видимый текст vs кросс-раскладка vs контекст последовательности) и покрыть **табличными** тестами вход→решение. Это снимет дублирование render+dict и устранит языковые хардкоды.

### 1.2 [HIGH] ✅ Хардкод исправлений под конкретные слова

```swift
// SpellingSuggestionProvider.swift:59-64
private static let curatedSuggestions: [LanguageID: [String: [String]]] = [
    .ru: [
        "заклучил": ["заключил"],
        "закулчил": ["заключил"]
    ]
]
```

То же слово «заключил» одновременно:
- добавлено в `LayoutSwitcher/Dictionary/Resources/ru.txt` (диф);
- добавлено в in-memory словари тест-фикстур (`TypingPipelineTests.swift`, `+["заключил", "мир"]`);
- зашито в `FixedSuggestionProvider` тестов (`"Заклучил"/"Закулчил" → "заключил"`, `"еир" → "мир"`).

Это оверфиттинг: общий `CupertinoCorrector` эти транспозиции не вытягивает, поэтому слова прибиты гвоздями ради конкретных тестов (`pendingRussianSequenceCanAbsorbVisibleEnglishAcronymWithRussianCorrection` ожидает ровно «Заключил мир»).

**Риск:** не масштабируется (каждое новое слово = новый хардкод); даёт ложную уверенность (тесты зелёные, алгоритм не изменился); продакшн-словарь и логика подгоняются под тест-данные.

**Рекомендация:** лечить причину, а не симптом.
- (a) Поправить ранжирование/пороги `CupertinoCorrector` так, чтобы транспозиционные опечатки (Дамерау—Левенштейн с обменом соседних) типа `заклучил→заключил` ловились в общем виде.
- (b) Если курируемый словарь намеренный — вынести его в ресурс-данные (json/txt), а не в исходник; задокументировать политику; тестом закрепить, что это **fallback** перед системными guesses, а не основной путь.
- Убрать пер-тестовые слова из продакшн-словаря, если они не нужны вне теста.

### 1.3 [MED] ✅ Две почти дублирующие точки входа в детекторе

`LayoutDetector.decide()` (`LayoutSwitcher/Detector/LayoutDetector.swift:166-498`) и `decideVisibleTextCorrection()` (`:556-656`) обе реализуют один каскад однокоренных коррекций (RO-диакритика → ё → двойная заглавная → дубль-буква → cupertino) в одном порядке, но с тонкими отличиями (например, `decide` дополнительно прогоняет кросс-раскладку и `shouldKeepNonConvertibleRaw`). Фикс в одной ветке легко не продублировать в другой.

**Рекомендация:** вынести общий «каскад однокоренных коррекций» в один приватный хелпер, который вызывают обе точки входа.

### 1.4 [MED] ✅ `shouldKeepNonConvertibleRaw` — ещё один полный ре-рендер

```swift
// LayoutDetector.swift:500-526 (новое в дифе)
for language in LanguageID.allCases where language != activeLanguage {
    ...
    let rendered = mapping.render(buffer, in: language)   // полный ре-рендер
    guard rendered != raw, wordMatchesAlphabet(...), dictionaries[language]?.contains(rendered) == true
    else { continue }
    return false
}
```

Для токена, который `NonConvertibleTokenGuard` хочет сохранить и который содержит неоднозначный символ (`;`→`ж`, `]`→`ъ` и т.п.), перебираются все языки с рендером и dict-проверкой — внутри `decide()` на main thread. По перфу мелочь, но это снова дублирует render+dict-логику (см. 1.1) и должно уехать в единую модель решения.

### 1.5 [LOW] ✅ Непоследовательный ключ микрокэша

```swift
// LayoutDetector.swift:241
let missKey = "\(candidate.language.rawValue)\u{0}\(candidate.text)"
```

Соседние кэши в той же функции — вложенные словари `[String:[LanguageID:Double]]` (`:222-223`). Здесь же — строковая склейка через `\u{0}`. Не баг (нулевых байтов в пользовательском тексте не бывает), но непоследовательно. Привести к общему виду (`Set<...>` по структуре или вложенный словарь).

---

## 3. Конкуррентность / перформанс на пути ввода

### 2.1 [MED] ✅ Детекция выполняется синхронно на main thread в callback event tap

Путь события: `tapCallback` → `MainActor.assumeIsolated` (`LayoutSwitcher/EventTap/KeyboardEventTap.swift:90-116`) → `handle` (`:67-88`) → `buffer.commit` → `onCommitted` (`TypingPipeline.swift:126-136`) → `evaluate` (`:178-270`) → `detector.decide()` + видимые/контекстные коррекции.

Внутри `decide()` на промахе кэша вызывается системный `NSSpellChecker.checkSpelling` синхронно:

```swift
// SystemSpellChecker.swift:67-73, 92-106 — contains() с FIFO-кэшем на 10_000 (:34)
func contains(_ word: String) -> Bool {
    let normalized = word.lowercased()
    if let cached = cache[normalized] { return cached }
    let result = lookup(normalized)            // checker.checkSpelling — IPC к системе
    insertIntoCache(normalized, result: result)
    return result
}
```

А путь cupertino-коррекции (`SystemSpellingSuggestionProvider.suggestions` → `checker.guesses`, `SpellingSuggestionProvider.swift:20-33`) **вообще без кэша** — каждый подходящий токен при включённом `correctCommonTypos` синхронно дёргает `NSSpellChecker.guesses` на main thread.

`Roadmap.md:14` прямо предписывает обратное: «CGEventTap callback крутится на main run loop → тяжёлый анализ должен уходить на фоновую очередь». Реализация делает тяжёлый анализ (composite-словарь с системным spell-check, n-граммы, несколько полных ре-рендеров, uncached guesses) синхронно в callback.

**Риск:** у tap есть системный watchdog (`tapDisabledByTimeout`, обрабатывается перевзводом на `:68-74`); тяжёлая main-thread работа = риск лага ввода и, в пределе, отключения tap с потерей события. Главный источник задержки — `NSSpellChecker` на «холодных»/новых словах (системный IPC); FIFO-кэш 10k спасает только `contains()` и только в установившемся режиме, а `guesses` не кэширован вовсе.

**Рекомендация:** померить worst-case `decide()` (особенно промах spell-check и `guesses`). Если ощутимо — вынести скоринг/spell-check с main thread (детектор чист и Sendable-дружелюбен) либо прогревать кэш и кэшировать `guesses`. На callback-пути оставить только синхронное решение о подавлении хоткея (`KeyboardEventTap.handle:80-85`), а детекцию слова делать асинхронно. Минимум — задокументировать отклонение от Roadmap и добавить перф-тест с бюджетом задержки.

### 2.2 [LOW] ✅ `waitForLayout` — фиксированный таймаут 200 мс + busy-poll

```swift
// Retyper.swift:368-381
private func waitForLayout(_ id: String, timeoutNanoseconds: UInt64 = 200_000_000) async -> Bool {
    let step: UInt64 = 10_000_000  // 10 мс
    while elapsed <= timeoutNanoseconds {
        refreshCurrentLayout()                     // TIS-вызовы каждые 10 мс
        if currentLayoutIDProvider() == id { return true }
        await sleep(step); elapsed += step
    }
    ...
}
```

На медленной системе подтверждение `TISSelectInputSource` может не уложиться в 200 мс → retype прерывается. Это **безопасно** (прерывание до стирания, потеря — лишь пропущенная коррекция, не порча текста), но раздражает. Рекомендация: сделать таймаут конфигурируемым/чуть больше (300–500 мс) и логировать фактическую задержку подтверждения для тюнинга.

---

## 4. Низкоуровневая корректность инъекции

### 3.1 [LOW] ✅ Счётчик backspace предполагает «1 нажатие = 1 стираемый символ»

```swift
// Retyper.swift:221 (и :325 в sequence-пути)
let charsToErase = original.count + 1   // original = [WordChar], по одному на нажатие
for _ in 0..<charsToErase { postKeyEvent(51, []) } // 51 = backspace
```

`original` — массив нажатий, не графем. Для поддерживаемых RU/EN/UK/RO через keycode-маппинг (и `kUCKeyTranslateNoDeadKeysBit` в энкодере) соотношение обычно 1:1, но это **неявный инвариант**: dead-key/комбинирующая последовательность может дать иное число экранных символов. Рекомендация: задокументировать инвариант либо считать число backspace по графемам отрендеренного `originalText`.

### 3.2 [INFO] ✅ Хардкод кейкодов разделителей/стирания

`51` backspace, `49` space, `36` enter, `48` tab, `9` ⌘V (`Retyper.swift:194-200,221-223,325-327`; `SmartPaste.swift:68`). Стандартны для всех раскладок — ок, но именованные константы читались бы лучше.

### 3.3 [INFO] ✅ `postUnicode` через `virtualKey: 0` + `keyboardSetUnicodeString`

`Retyper.swift:397-412` — рабочий и распространённый способ ввода произвольного Unicode (используется для пунктуации-разделителя после смены раскладки, чтобы её не переинтерпретировали). Не «deprecated». Оставить.

---

## 5. Дистрибуция / конфиг

### 4.1 [HIGH] ✅ `MACOSX_DEPLOYMENT_TARGET = 15.7`

В `LayoutSwitcher.xcodeproj/project.pbxproj` цель развёртывания — именно **15.7** (свежий точечный релиз Sequoia), тогда как `Roadmap.md` целился в 15.0 (`INFOPLIST_KEY_LSMinimumSystemVersion = 15.0`). Это отсекает всех пользователей 15.0–15.6 (и, очевидно, <15) — почти наверняка непреднамеренное завышение.

**Рекомендация:** опустить до 15.0 (или даже 14.x, если нет 15-only API). Проверить: собрать с `MACOSX_DEPLOYMENT_TARGET=15.0` — если компилируется и тесты зелёные, 15.7-only API нет и планку надо снижать.

### 4.2 [LOW] ✅ Несовпадение subsystem логгера и bundle id

Bundle id — `GM.LayoutSwitcher` (`PRODUCT_BUNDLE_IDENTIFIER` в pbxproj), а все `os.Logger` в коде используют `subsystem: "GIH.LayoutSwitcher"` (например `LayoutDetector.swift:53`, `TypingPipeline.swift:12`, `KeyboardEventTap.swift:8`, `Retyper.swift:82`, `SystemSpellChecker.swift:32` и т.д.). Фильтрация `log show --predicate 'subsystem == "GM.LayoutSwitcher"'` ничего не покажет. Свести к одному значению (лучше к bundle id) через единую константу.

### 4.3 [INFO] ✅ Entitlements корректны для CGEventTap

`LayoutSwitcher.entitlements`: `app-sandbox = false`, `device.input-monitoring = true`; в pbxproj `ENABLE_APP_SANDBOX = NO`, `ENABLE_HARDENED_RUNTIME = YES`, `INFOPLIST_KEY_LSUIElement = YES`, `SWIFT_VERSION = 6.0`. Это правильная комбинация для приложения с глобальным event tap: MAS невозможен (только Developer ID + нотаризация), что согласуется с Roadmap. Хорошо.

### 4.4 [LOW] ✅ Нет явного Info.plist

`GENERATE_INFOPLIST_FILE = YES` — Info.plist генерируется. Пока ок; при будущем добавлении usage-строк/URL-схем помнить, что они управляются через build settings (`INFOPLIST_KEY_*`), а не через файл.

---

## 6. Тесты

### 5.1 [MED] ✅ Тесты «зелёные по построению» из-за хардкод-слов

Новые тесты (`TypingPipelineTests.swift`, диф) ожидают точные строки «Заключил мир», «заключил», «мир», опираясь на курируемый словарь (1.2) + посеянные in-memory словари + `FixedSuggestionProvider`. Они зелёные не за счёт общего алгоритма, а за счёт тест-данных: стерегут регрессии конкретных спец-кейсов, но создают ложное ощущение корректности общего пути.

**Рекомендация:** оставить как сценарные регрессионные, но добавить параметрические/property-тесты на общий typo/кросс-раскладочный путь (наборы вход→ожидаемое решение без подсева ровно нужного слова) и тест, фиксирующий, что курируемый словарь — именно fallback.

### 5.2 [LOW] ✅ Реальные `sleep` в тестах

Часть тестов использует `waitForAsyncWorkWindow(nanoseconds:)` (реальные паузы). `Swift6CodeQualityAudit.md` уже отмечал `Task.sleep` в тестах. Это снижает детерминизм и замедляет прогон. Предпочесть условные ожидания (`waitUntil { ... }`) единообразно; реальные паузы оставить лишь там, где иначе нельзя.

### 5.3 ⚠️[LOW] Пробелы покрытия (по карте, не проверено построчно)

Нет живого CGEventTap-интеграционного теста (callback мокается); нет стресс-тестов (быстрый ввод / частое переключение приложений); ограниченные UI-тесты; не покрыт dead-key/комбинирующий ввод (связано с 3.1).

---

## 7. Документация (явный запрос пользователя)

### Инвентарь `LayoutSwitcher/docs/`

| Файл | Размер | Оценка |
|------|--------|--------|
| `Roadmap.md` | 29 КБ | Добротный фазовый план. Блок «что уже есть» описывает стартовый *шаблон* (пишет «App Sandbox включён» — сейчас выключен); это историческая запись, ок. **Дрейф:** требование «тяжёлый анализ вне main run loop» (`:14`) не выполнено — см. 2.1. |
| `PuntoCarambaParity.md` | 65 КБ | Матрица паритета с конкурентами. Не проверял на актуальность построчно. |
| `Swift6CodeQualityAudit.md` | **427 КБ** | Прошлый аудit от 2026-05-12. Огромен и, вероятно, частично устарел/повторяющийся. Кандидат на сжатие/замену. Текущий отчёт его дополняет (см. §8). |
| `ManualLiveSmokeTest.md` | 3.4 КБ | Хороший ручной гейт (TextEdit/Notes, ложные срабатывания на `account`, `ванна`, `класс`, `сумма`). |
| `nonfunctionsl.txt` | 9.8 КБ | **Опечатка в имени** («nonfunctionsl»). Переименовать в `nonfunctional.md`, перевести в markdown, проверить на актуальность. |

### Рекомендации по докам
- Обновить `Roadmap.md` под фактическую модель (синхронная детекция на main) **или** реализовать вынос анализа в фон (2.1) и привести код в соответствие.
- Дополнить `ManualLiveSmokeTest.md` новыми сценариями коррекции (поглощение акронима, последовательности `заключил/мир`) и пунктом проверки задержки ввода.
- После рефакторинга 1.1 добавить короткий `docs/DecisionModel.md` с моделью приоритетов решения — это снизит риск повторного whack-a-mole.

---

## 8. Что закрыто / открыто относительно `Swift6CodeQualityAudit.md`

Прошлый аудит фиксировал сильные стороны (Swift 6, `@MainActor`, DI, `privacy: .public` в логах, отсутствие `try!/as!/force unwrap` в продакшене) и зоны риска на границе с macOS API (синхронные мосты через `MainActor.assumeIsolated`, `unsafeBitCast` в AX после ручной проверки типа, неаннотированные DI-замыкания, `Task.sleep` в тестах).

- **Подтверждается и сейчас:** `MainActor.assumeIsolated` в мосте tap (`KeyboardEventTap.swift:113`) — обоснован и задокументирован; `Task.sleep`/реальные паузы в тестах (см. 5.2).
- **Новое в этом аудите (не покрыто прежним):** разрастание логики решения (1.1), хардкод слов (1.2), дрейф «анализ на main thread» vs Roadmap (2.1), `deployment target 15.7` (4.1), mismatch subsystem/bundle id (4.2).

---

## 9. Приоритизированный backlog (без внесения изменений)

**Быстрые победы (низкое усилие, заметный эффект):**
1. 4.1 — снизить `MACOSX_DEPLOYMENT_TARGET` до 15.0 после проверочной сборки. **[HIGH/low effort]**
2. 4.2 — единая константа subsystem = bundle id. **[LOW/low effort]**
3. 2.2 — поднять/конфигурировать таймаут `waitForLayout`, логировать факт. задержку. **[LOW/low effort]**
4. 6.* — переименовать `nonfunctionsl.txt`, освежить Roadmap. **[LOW/low effort]**

**Среднесрочно:**
5. 1.2 — устранить хардкод слов: общий typo-путь либо вынесенный data-fallback. **[HIGH/medium]**
6. 2.1 — измерить задержку `decide()`/`guesses`; кэшировать guesses или вынести в фон. **[MED/medium]**
7. 1.3 / 1.4 — слить дублирующие каскады и ре-рендеры. **[MED/medium]**
8. 5.1 / 5.2 — параметрические тесты общего пути; убрать реальные паузы. **[MED/medium]**

**Крупная работа (скоупить отдельно):**
9. 1.1 — единая модель решения в детекторе + `DecisionContext`; пайплайн как оркестратор; табличные тесты; `docs/DecisionModel.md`. **[HIGH/large]** Это корень всей недавней серии `fix:`-коммитов.

---

## 10. Проверено и в порядке (не находки)

- **Безопасность retype:** двухфазность (префлайт без разрушающих действий → деструктивная фаза) корректна; при невозможности закодировать символ или подтвердить раскладку операция прерывается до стирания (`Retyper.swift:147-215`, `:271-320`). ✅
- **Защита от петли обратной связи:** `SyntheticEventFilter` помечает синтетические события через `eventSourceUserData`, tap их игнорирует (`KeyboardEventTap.swift:76-78`). Риск коллизии пренебрежим. ✅
- **Cooldown / антишторм:** `RetypeDispatcher` корректно гасит повтор одной и той же коррекции по ключу `(kind,original,corrected,source,target,bundleID)` с истечением (`RetypeDispatcher.swift:282-321`). ✅
- **Коалесинг последовательностей:** `SequenceDetector` (флаш по 3+ словам / закрывающей пунктуации / 120 мс простоя, longPause 2 с) — чистый, на инъектируемом `sleep` (`SequenceDetector.swift`). ✅
- **SmartPaste:** определение языка по скрипту (`SmartPaste.swift:94-108`) выбирает лишь раскладку назначения перед ⌘V; **сам текст вставляется буквально** (⌘V), раскладка влияет только на последующий ввод. Поэтому это не баг корректности, а эвристика «какую раскладку оставить активной». ✅ (мелкое замечание: смешанный текст разрешается по приоритету UK→RU→RO→EN; при желании можно выбирать по плотности скрипта.)
- **Изоляция конкуррентности:** ключевые сервисы `@MainActor`; гонок в горячем пути не обнаружено. ✅
