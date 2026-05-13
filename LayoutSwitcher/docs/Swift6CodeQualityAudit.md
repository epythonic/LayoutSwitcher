# Аудит качества кода Swift 6

Дата первого прохода: 2026-05-12

Статус: шаг 1, статический аудит без запуска `xcodebuild build` и `xcodebuild test`; шаг 2, первая малая правка качества кода.

## Область первого прохода

Цель первого прохода — проверить не весь проект построчно, а базовый слой качества Swift 6:

- настройки Xcode-проекта;
- изоляцию mutable-состояния через `@MainActor`;
- DI для системных побочных эффектов;
- низкоуровневые мосты `CGEventTap`, Carbon, AX, TIS, pasteboard;
- использование `Result`-подобных enum вместо recoverable `throws`;
- базовую дисциплину тестов Swift Testing.

Проверенные файлы:

- `LayoutSwitcher.xcodeproj/project.pbxproj`
- `LayoutSwitcher/App/AppState.swift`
- `LayoutSwitcher/Buffer/WordBuffer.swift`
- `LayoutSwitcher/Pipeline/TypingPipeline.swift`
- `LayoutSwitcher/Pipeline/RetypeDispatcher.swift`
- `LayoutSwitcher/Pipeline/SequenceDetector.swift`
- `LayoutSwitcher/Pipeline/ManualActionsCoordinator.swift`
- `LayoutSwitcher/Mapping/Retyper.swift`
- `LayoutSwitcher/Mapping/SelectionConverter.swift`
- `LayoutSwitcher/Mapping/SmartPaste.swift`
- `LayoutSwitcher/EventTap/KeyboardEventTap.swift`
- `LayoutSwitcher/EventTap/SecureInputObserver.swift`
- `LayoutSwitcher/EventTap/AccessibilityPermission.swift`
- `LayoutSwitcher/Hotkeys/HotkeyCoordinator.swift`
- `LayoutSwitcher/Hotkeys/CarbonHotkeyManager.swift`
- `LayoutSwitcher/InputSource/InputSourceManager.swift`
- `LayoutSwitcher/Stats/FocusedAppObserver.swift`
- выборочные проверки `LayoutSwitcherTests/*.swift`

## Краткий вердикт

Базовая архитектура выглядит сильной для Swift 6: основные mutable-сервисы изолированы `@MainActor`, зависимости в ключевых потоках инъектируются через initializer closures, пользовательские данные в логах в основном помечены `privacy: .public`, а production-код не показывает явных `try!`, `as!`, force unwrap или `XCTest`.

Главные зоны риска не в бизнес-логике, а на границе с macOS API:

- синхронные callback-мосты используют `MainActor.assumeIsolated`;
- AX-код использует `unsafeBitCast` после ручной проверки типа;
- часть DI-closures не аннотирована `@MainActor` / `@Sendable`;
- в тестах есть прямые `Task.sleep`, что снижает детерминизм.

Критических дефектов уровня "немедленно ломает Swift 6" в первом статическом проходе не найдено. Но есть несколько мест, которые стоит укрепить до полного аудита сборкой и тестами.

## Подтвержденные сильные стороны

### 1. Проект переведен на Swift 6

В `project.pbxproj` найдено `SWIFT_VERSION = 6.0` для targets/configurations.

Также включен hardened runtime:

- `ENABLE_HARDENED_RUNTIME = YES`
- `MACOSX_DEPLOYMENT_TARGET = 15.7`

Ограничение: в этом шаге сборка не запускалась, поэтому фактический статус "zero warnings" не подтвержден.

### 2. Mutable-состояние в ядре в основном изолировано `@MainActor`

Подтвержденные примеры:

- `AppState` объявлен как `@MainActor @Observable final class`.
- `WordBuffer` объявлен как `@MainActor final class`.
- `TypingPipeline`, `RetypeDispatcher`, `SequenceDetector`, `ManualActionsCoordinator`, `Retyper`, `HotkeyCoordinator`, `KeyboardEventTap`, `InputSourceManager`, `FocusedAppObserver` также находятся на `@MainActor`.

Это хорошо совпадает с правилом проекта: shared mutable state должен быть изолирован на main actor.

### 3. DI для побочных эффектов реализован лучше среднего

Хорошие примеры:

- `Retyper` принимает closures для enabled layouts, current layout, refresh, select, sleep, key posting, unicode posting.
- `TypingPipeline` принимает `sleepBeforeSequenceFlush`.
- `SelectionConverter` имеет test initializer с closures для AX element, pasteboard, key posting и sleep.
- `SmartPaste` имеет test initializer для pasteboard, key posting и sleep.
- `FocusedAppObserver` принимает `FocusedRoleProviding`.

Это делает код тестируемым без реальных keyboard layouts, pasteboard, AX или CGEvent.

### 4. Error handling в production-коде в целом доменный

Хорошие примеры:

- `RetypeResult` и `RetypeFailureReason` возвращают явные причины отказа.
- `SelectionConverter.Result` возвращает `success` / `failure(Reason)`.
- `SmartPaste.Result` моделирует ожидаемые исходы без исключений.

По статическому поиску recoverable `throws` в production-коде не выявлены. Найдены только `async throws` в отдельных tests, что не выглядит нарушением доменного error handling production-кода.

### 5. Логи в проверенных потоках читаемые и privacy-aware

Во многих местах пользовательский текст и bundle identifiers логируются через `privacy: .public`, например:

- committed word в `TypingPipeline`;
- retype original/corrected text в `Retyper`;
- focused app context в `FocusedAppObserver`;
- selection/smart-paste decisions.

Это совпадает с правилом проекта про privacy-first logging.

### 6. Тестовый стек в основном соответствует Swift Testing

По выборочной проверке:

- тесты используют `import Testing`;
- test structs объявлены как `@MainActor`;
- assertions используют `#expect`;
- `import XCTest` не найден.

## Найденные риски и рекомендации

## Выполненные улучшения

### Шаг 2. Сужены небезопасные мосты main actor и AX

Изменения:

- добавлен `AXElementBridge`, который централизует единственный `unsafeBitCast` из `CFTypeRef` в `AXUIElement`;
- `FocusedAppObserver` и `SelectionConverter` теперь используют этот helper вместо локального повторения `unsafeBitCast`;
- `SecureInputObserver` больше не использует `MainActor.assumeIsolated` в `Timer` callback и переходит на `Task { @MainActor ... }`;
- `KeyboardEventTap` и `CarbonHotkeyManager` получили main-thread guard перед `MainActor.assumeIsolated` и комментарий-инвариант.

Ограничение:

Сборка и тесты после правки не запускались в рамках этого шага.

### Шаг 3. Усилен lifecycle retype-флага

Изменения:

- `RetypeDispatcher` теперь дополнительно защищает сброс `isRetyping` через `defer` в single-word и sequence retype tasks;
- `ManualActionsCoordinator` теперь дополнительно защищает `retypeDispatcher.setRetypingFlag(false)` через `defer` в ручном force-retype task.

Зачем:

Текущий retype flow не бросает исключения и уже сбрасывал флаг после `await`. `defer` добавлен как страховка от будущих early-return внутри async-блоков, чтобы pipeline не мог остаться в состоянии "retype идет" после частично измененного кода.

Ограничение:

Сборка и тесты после правки не запускались в рамках этого шага.

### Шаг 4. Явно зафиксированы main-actor side-effect closures

Изменения:

- в `Retyper` side-effect closures для layout lookup/selection, sleep и event posting теперь типизированы как `@MainActor`;
- в `SelectionConverter` closures для AX, pasteboard, key posting и sleep теперь типизированы как `@MainActor`;
- в `SmartPaste` closures для pasteboard, key posting и sleep теперь типизированы как `@MainActor`.

Зачем:

Классы и раньше были `@MainActor`, но side-effect dependencies не выражали actor expectation в собственных типах. Теперь контракт явнее: эти closures должны вызываться в main-actor контексте, что лучше соответствует Swift 6 strict concurrency и macOS UI/API ограничениям.

Ограничение:

`@Sendable` намеренно не добавлен массово на этом шаге. Часть closures захватывает main-actor macOS dependencies; sendability нужно проверять точечно после сборки.

Сборка и тесты после правки не запускались в рамках этого шага.

### Шаг 5. Добавлен `Sendable` для чистых DTO

Изменения:

- `LanguageID` и `LanguagePair` теперь `Sendable`;
- `WordSeparator`, `WordResetReason`, `KeyCodeKind` теперь `Sendable`;
- `WordChar` и `CommittedWord` теперь `Sendable`;
- `PendingRetypeCandidate` теперь `Sendable`;
- `AutoSwitchRecord` теперь `Sendable`;
- `RetypeFailureReason` и `RetypeResult` теперь `Sendable`;
- `AutoSwitchCooldownEntry` и его `Kind` теперь `Sendable`.

Зачем:

Эти типы являются value snapshots, которые используются вокруг async/main-actor потоков retype, pipeline, undo и cooldown. Явный `Sendable` делает Swift 6 contract понятнее и заранее отделяет безопасные DTO от типов, завязанных на macOS references.

Ограничение:

`RetypeInputSource` намеренно не помечен `Sendable` на этом шаге, потому что хранит `InputSource?`, а `InputSource` является wrapper вокруг TIS reference. Для него нужен отдельный compile-backed анализ.

Сборка и тесты после правки не запускались в рамках этого шага.

### Шаг 6. Убраны безымянные sleeps из части тестовых сценариев

Изменения:

- в `TypingPipelineTests` прямые ожидания `Task.sleep(nanoseconds: ...)` в сценариях заменены на `waitForAsyncWorkWindow(nanoseconds:)`;
- в `HotkeyCoordinatorTests` polling step внутри `waitUntil` вынесен в отдельный helper `waitForPollingStep(nanoseconds:)`.

Зачем:

Это подготовительный шаг к полной детерминизации тестов. Сами сценарии теперь явно говорят, что ждут окно async-работы, а не просто "спят" магическое количество времени. Полностью от реального времени тесты пока не избавлены.

Ограничение:

Внутри helper-слоя все еще используется `Task.sleep`; для окончательного исправления нужен controlled-delay подход или тестовые сигналы от async retype/sequence flow.

Сборка и тесты после правки не запускались в рамках этого шага.

### Шаг 7. Убран дублирующийся сброс retype-флага

Изменения:

- в `RetypeDispatcher` удалены ручные `self.isRetyping = false` после `await`, потому что сброс теперь централизован в `defer`;
- в `ManualActionsCoordinator` удален ручной `setRetypingFlag(false)` после `await`, потому что сброс теперь централизован в `defer`.

Зачем:

После шага 3 код временно имел два места сброса одного и того же флага: `defer` и явную строку после async-вызова. Шаг 7 оставляет один источник истины для lifecycle cleanup и снижает риск будущего расхождения между автоматическим и ручным retype flow.

Ограничение:

Сборка и тесты после правки не запускались в рамках этого шага.

### Шаг 8. Время в `RetypeDispatcher` стало инъектируемым

Изменения:

- `RetypeDispatcher` получил dependency `now: @MainActor () -> Date` с production default `Date.init`;
- timestamps для `AutoSwitchRecord` и `RecentSwitchEntry` теперь берутся через `now()`;
- cooldown comparison и `expiresAt` теперь также используют `now()`.

Зачем:

Раньше `RetypeDispatcher` напрямую вызывал `Date()`, из-за чего cooldown/record lifecycle был привязан к системным часам. Инъекция времени повышает тестируемость и соответствует общему DI-паттерну проекта: побочные эффекты и mutable runtime context проходят через initializer dependencies.

Ограничение:

Сборка и тесты после правки не запускались в рамках этого шага.

### Шаг 9. Время в `ManualActionsCoordinator` стало инъектируемым

Изменения:

- `ManualActionsCoordinator` получил dependency `now: @MainActor () -> Date` с production default `Date.init`;
- `collectLastSentenceWords()` больше не вызывает `Date()` напрямую и использует `currentTime = now()`.

Зачем:

Manual sentence conversion отбрасывает слишком старые слова по возрасту. Раньше эта логика была привязана к системным часам, теперь ее можно тестировать через injected time без реального ожидания.

Ограничение:

Сборка и тесты после правки не запускались в рамках этого шага.

### Шаг 10. Время commit в `WordBuffer` стало инъектируемым

Изменения:

- `WordBuffer` получил dependency `now: @MainActor () -> Date` с production default `Date.init`;
- `CommittedWord.committedAt` теперь выставляется через `now()`, а не через прямой `Date()`.

Зачем:

`CommittedWord.committedAt` участвует в sequence detection, cooldown matching, manual sentence conversion и undo/manual windows. Инъекция времени позволяет строить deterministic tests вокруг этих сценариев без ожидания реального времени.

Ограничение:

Сборка и тесты после правки не запускались в рамках этого шага.

### Шаг 11. Clock поднят на уровень `TypingPipeline`

Изменения:

- `TypingPipeline` получил dependency `now: @MainActor () -> Date` с production default `Date.init`;
- этот clock прокидывается в `RetypeDispatcher`;
- этот clock прокидывается в `ManualActionsCoordinator`;
- retroactive auto-extend scan больше не вызывает `Date()` напрямую и использует `currentTime = now()`.

Зачем:

Auto-switch, cooldown, recent-switch timestamps, sentence age filtering и retroactive scan теперь могут работать от одного injected clock. Это делает future tests менее зависимыми от системного времени и убирает рассинхрон между разными частями одного retype-flow.

Ограничение:

Сборка и тесты после правки не запускались в рамках этого шага.

### Шаг 12. `HotkeyCoordinator` последовательно использует injected time

Изменения:

- `HotkeyCoordinator.now` теперь типизирован как `@MainActor () -> Date`;
- manual recent-switch timestamp больше не вызывает `Date()` напрямую и использует `now()`.

Зачем:

`HotkeyCoordinator` уже использовал injected clock для manual/undo windows, но запись manual recent entry брала системное время напрямую. Теперь весь hotkey lifecycle опирается на один clock, что снижает расхождение в тестах и runtime-логике.

Ограничение:

Сборка и тесты после правки не запускались в рамках этого шага.

### Шаг 13. Убраны оставшиеся прямые `Date()` из runtime-счетчиков и learning flow

Изменения:

- `AppState.now` теперь типизирован как `@MainActor () -> Date`;
- `HotkeyCoordinator` теперь использует `now()` для timestamp manual selection conversion;
- `UsageStats` получил dependency `now: @MainActor () -> Date` и использует его для day rollover;
- `LearningCache` получил dependency `now: @MainActor () -> Date` и использует его для timestamp learned undo entry.

Зачем:

После предыдущих шагов большая часть pipeline уже работала от injected clock, но daily stats, learned undo entries и один hotkey timestamp все еще читали системное время напрямую. Теперь эти участки можно тестировать управляемым временем без реального ожидания и без зависимости от календарного дня машины.

Ограничение:

Default `Date.init` в initializer'ах оставлен как production fallback. Сборка и тесты после правки не запускались в рамках этого шага.

### Шаг 14. Добавлен `Sendable` для persisted/read-only DTO

Изменения:

- `RecentSwitchEntry` теперь `Sendable`;
- `RecentSwitchEntry.Kind` теперь `Sendable`;
- private `LearningCache.Entry` теперь `Sendable`;
- `LearningCache.LearnedEntry` теперь `Sendable`.

Зачем:

Эти типы являются immutable snapshots для истории переключений и learned undo entries. Они состоят из value-safe полей (`String`, `Date`, `UUID`, enum, optional), поэтому явный `Sendable` помогает Swift 6 яснее видеть, что данные можно безопасно передавать как снимки, не смешивая их с main-actor mutable state.

Ограничение:

Сборка и тесты после правки не запускались в рамках этого шага.

### Шаг 15. Добавлен `Sendable` для manual action result DTO

Изменения:

- `SelectionConverter.Result` теперь `Sendable`;
- `SelectionConverter.Result.Conversion` теперь `Sendable`;
- `SelectionConverter.Result.Method` теперь `Sendable`;
- `SelectionConverter.Result.Reason` теперь `Sendable`;
- `SmartPaste.Result` теперь `Sendable`.

Зачем:

Эти result-типы являются immutable value DTO, возвращаемыми из async manual actions. Явный `Sendable` делает их безопасный статус понятным для Swift 6 и не затрагивает macOS side-effect closures, которые остаются main-actor dependencies.

Ограничение:

Сборка и тесты после правки не запускались в рамках этого шага.

### Шаг 16. Добавлен `Sendable` для keyboard/hotkey value payloads

Изменения:

- `KeyEvent` теперь `Sendable`;
- `KeyEvent.Kind` теперь `Sendable`;
- `HotkeyAction` теперь `Sendable`;
- `HotkeyDefinition` теперь `Sendable`;
- `HotkeyDefinition.ModifierMask` теперь `Sendable`.

Зачем:

Эти типы являются compact value payloads для event routing и hotkey matching. Они состоят из value-safe полей (`String`, integers, CoreGraphics value aliases/options), поэтому явный `Sendable` улучшает Swift 6 concurrency contract без изменения поведения.

Ограничение:

`InputSource` намеренно не помечен `Sendable`, потому что содержит `TISInputSource?`. Его нужно рассматривать отдельно: либо отделять sendable snapshot от live TIS reference, либо подтверждать решение сборкой.

Сборка и тесты после правки не запускались в рамках этого шага.

### Шаг 17. Добавлен безопасный snapshot для `InputSource`

Изменения:

- добавлен `InputSourceSnapshot: Identifiable, Hashable, Sendable`;
- `InputSourceSnapshot` содержит только immutable metadata: `id`, `localizedName`, `primaryLanguage`, `isSelectable`, `isEnabled`, `isKeyboardLayout`;
- `InputSource` получил accessor `snapshot`, который возвращает DTO без live `TISInputSource` reference.

Зачем:

`InputSource` нельзя бездумно помечать `Sendable`, потому что он хранит `TISInputSource?`. Новый snapshot отделяет безопасные данные от live Carbon reference и дает проекту очевидный DTO для UI, тестов и будущих async boundaries.

Ограничение:

Сам `InputSource` намеренно остается без `Sendable`. Сборка и тесты после правки не запускались в рамках этого шага.

### Шаг 18. Snapshot API начал использоваться в UI-only layout metadata

Изменения:

- `InputSourceManaging` получил read-only snapshot helpers: `currentSnapshot`, `keyboardLayoutSnapshots()`, `enabledLayoutSnapshots()`;
- добавлен `LayoutPairSnapshot: Hashable, Sendable`;
- `LayoutPairResolver` получил `autoDetectSnapshots(from:)` для metadata-only pair detection;
- `LayoutsTab` теперь использует `InputSourceSnapshot` и `LayoutPairSnapshot` для отображения текущей раскладки, списка активных раскладок и найденных пар.

Зачем:

`LayoutsTab` только отображает metadata и не вызывает `select(_:)`, поэтому ему не нужен live `TISInputSource` reference. Перевод этого UI-only участка на snapshots уменьшает распространение Carbon-backed объектов в SwiftUI слое и делает границу live system API более явной.

Ограничение:

Старый `LayoutPairResolver.autoDetect(from:)` оставлен для совместимости с live `InputSource` flows. Сборка и тесты после правки не запускались в рамках этого шага.

### Шаг 19. `OnboardingView` переведен на layout snapshots

Изменения:

- onboarding step `.layouts` теперь читает `inputSources.enabledLayoutSnapshots()` вместо live `enabledLayouts()`.

Зачем:

Onboarding только отображает названия активных раскладок и не выполняет selection/system actions. Поэтому live `TISInputSource` reference ему не нужен. Это еще один UI-only участок, где metadata отделена от Carbon-backed объекта.

Ограничение:

Сборка и тесты после правки не запускались в рамках этого шага.

### Шаг 20. `PerAppLayoutsTab` переведен на layout snapshots

Изменения:

- `availableLayouts` теперь возвращает `[InputSourceSnapshot]`;
- picker per-app layout использует metadata snapshots для label/id;
- initial layout при добавлении приложения теперь берется из `currentSnapshot`.

Зачем:

Экран per-app layouts сохраняет только layout id и показывает localized name. Ему не нужен live `TISInputSource` reference. Перевод на snapshots уменьшает распространение Carbon-backed объектов в SwiftUI settings layer.

Ограничение:

Системный `NSOpenPanel` остается runtime side effect этого UI-экрана и не относится к `InputSource` snapshot cleanup. Сборка и тесты после правки не запускались в рамках этого шага.

### Шаг 21. Read-only layout labels/badges в `AppDelegate` переведены на snapshots

Изменения:

- initial `appState.currentLayoutID` теперь берется из `inputSources.currentSnapshot`;
- `inputSources.onChange` превращает live `InputSource` в snapshot перед обновлением label/badge;
- snooze/focus/status badge refresh теперь читает `currentSnapshot.primaryLanguage`.

Зачем:

`AppDelegate` в этих местах только обновляет user-facing label и status item badge. Для этого достаточно metadata snapshot, live `TISInputSource` reference не нужен. Это продолжает сужать область распространения Carbon-backed объектов.

Ограничение:

`inputSources.onChange` все еще получает live `InputSource?`, потому что это существующий manager callback. Сборка и тесты после правки не запускались в рамках этого шага.

### Шаг 22. Добавлен snapshot-oriented layout change callback

Изменения:

- `InputSourceManager` получил `onSnapshotChange: ((InputSourceSnapshot?) -> Void)?`;
- при системной смене layout manager теперь вызывает и live `onChange`, и metadata-only `onSnapshotChange`;
- `AppDelegate` для UI label/badge подписан на `onSnapshotChange` вместо live `onChange`.

Зачем:

UI-подписке не нужен live `InputSource`. Новый callback позволяет read-only consumers получать безопасный snapshot, оставляя старый `onChange` для runtime-путей, где live object может понадобиться.

Ограничение:

Старый `onChange` сохранен для обратной совместимости. Сборка и тесты после правки не запускались в рамках этого шага.

### Шаг 23. Убрано дублирование в `LayoutPairResolver`

Изменения:

- `LayoutPairResolver.autoDetect(from:)` и `autoDetectSnapshots(from:)` теперь используют общий private generic helper;
- логика фильтрации enabled/selectable layouts, поиска English alternate и выбора RU/UK/RO primary layout больше не дублируется.

Зачем:

После добавления snapshot-flow live и metadata-only resolvers временно содержали одинаковый алгоритм. Общий helper снижает риск будущего расхождения: если правила auto-detect изменятся, их нужно будет менять в одном месте.

Ограничение:

Сборка и тесты после правки не запускались в рамках этого шага.

### Шаг 24. Исправлен generic accessor в `LayoutPairResolver`

Изменения:

- в private generic helper `autoDetectPairs` поиск English layout теперь использует переданный accessor `primaryLanguage($0)`;
- удалено некорректное обращение к `$0.primaryLanguage` на generic `Source`.

Зачем:

Шаг 23 убрал дублирование, но в одном месте оставил обращение к свойству, которого generic type не гарантирует. Шаг 24 исправляет эту compile-ошибку, сохраняя общий helper.

Ограничение:

Сборка и тесты после правки не запускались в рамках этого шага.

### Шаг 25. Добавлен snapshot lookup helper для enabled layouts

Изменения:

- `InputSourceManaging` получил helper `enabledLayoutSnapshot(id:)`;
- `PerAppLayoutsTab` использует `isAvailableLayout(_:)` поверх snapshot lookup вместо inline поиска по массиву.

Зачем:

Settings UI часто работает с сохраненными layout id и read-only metadata. Snapshot lookup helper снижает соблазн возвращаться к live `InputSource` ради простой проверки существования layout id и делает намерение кода понятнее.

Ограничение:

Сборка и тесты после правки не запускались в рамках этого шага.

### Шаг 26. Первый compile checkpoint и исправление `Self` в static callback closures

Проверка:

- `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS' -derivedDataPath /private/tmp/LayoutSwitcherDerivedData` упал на code signing: нет `Mac Development` certificate для team `J22XDKZ2HB`;
- compile-only rerun с `CODE_SIGNING_ALLOWED=NO` внутри обычного sandbox упал на `sandbox-exec: sandbox_apply: Operation not permitted`;
- compile-only rerun вне sandbox дошел до Swift diagnostics.

Найденные ошибки:

- `KeyboardEventTap.swift`: `covariant 'Self' type cannot be referenced from a stored property initializer`;
- `CarbonHotkeyManager.swift`: `covariant 'Self' type cannot be referenced from a stored property initializer`.

Исправление:

- в static callback closure `KeyboardEventTap` заменено `Self.logger` на `KeyboardEventTap.logger`;
- в static callback closure `CarbonHotkeyManager` заменено `Self.logger` на `CarbonHotkeyManager.logger`.

Ограничение:

После исправления требуется повторный compile-only build.

### Шаг 27. Исправлены warning из compile-only checkpoint

Проверка:

- повторный compile-only build с `CODE_SIGNING_ALLOWED=NO` завершился `BUILD SUCCEEDED`;
- при этом остались предупреждения, поэтому статус еще не был "zero warnings".

Исправления:

- `AXElementBridge` использует `unsafeDowncast` вместо `unsafeBitCast` после `CFGetTypeID` проверки;
- `NotificationManager.logger` помечен `nonisolated`, чтобы Sendable completion closures могли логировать без main-actor warning.

Ограничение:

После исправления требуется повторный compile-only build для подтверждения zero-warning статуса.

### Шаг 28. Compile-only build подтвержден

Проверка:

- команда: `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS' -derivedDataPath /private/tmp/LayoutSwitcherDerivedData CODE_SIGNING_ALLOWED=NO`;
- результат: `** BUILD SUCCEEDED **`.

Что подтверждено:

- Swift 6 compilation после шагов 2-27 проходит;
- source-level ошибки `Self` в static callback closures устранены;
- source-level warning `unsafeBitCast` в `AXElementBridge` устранен;
- source-level warning `NotificationManager.logger` из Sendable completion closure устранен.

Оставшийся шум/ограничения:

- обычный build без `CODE_SIGNING_ALLOWED=NO` падает из-за отсутствующего локального `Mac Development` certificate для team `J22XDKZ2HB`;
- Xcode пишет warning про выбор первого из нескольких macOS destinations;
- `appintentsmetadataprocessor` пишет warning: `Metadata extraction skipped. No AppIntents.framework dependency found.`;
- тесты в этом checkpoint не запускались.

### P1. `MainActor.assumeIsolated` используется как обязательный мост к callback API

Файлы:

- `LayoutSwitcher/EventTap/KeyboardEventTap.swift`
- `LayoutSwitcher/Hotkeys/CarbonHotkeyManager.swift`
- `LayoutSwitcher/EventTap/SecureInputObserver.swift`

Наблюдение:

- `KeyboardEventTap` ставит callback через `CGEvent.tapCreate`, затем в callback вызывает `MainActor.assumeIsolated`.
- `CarbonHotkeyManager` вызывает `MainActor.assumeIsolated` внутри Carbon `EventHandlerUPP`.
- `SecureInputObserver` до шага 2 вызывал `MainActor.assumeIsolated` внутри `Timer` callback; теперь использует `Task { @MainActor ... }`.

Почему это важно:

`MainActor.assumeIsolated` — это сознательный выход из compile-time safety Swift 6. Он корректен только если callback действительно выполняется на main actor. Для `CGEventTap` и Carbon это особенно чувствительно, потому что callback синхронный и не всегда можно заменить на `Task { @MainActor in ... }` без изменения поведения.

Рекомендация:

- Для оставшихся `assumeIsolated` держать короткий комментарий-инвариант: почему callback гарантированно приходит на main actor.
- Для оставшихся `assumeIsolated` держать дешевую проверку main thread там, где это безопасно.
- Не заменять `KeyboardEventTap` callback на async dispatch без отдельного анализа, потому что он должен синхронно вернуть `nil`, если hotkey consumed.

### P2. Retype lifecycle лучше защитить `defer`

Файлы:

- `LayoutSwitcher/Pipeline/RetypeDispatcher.swift`
- `LayoutSwitcher/Pipeline/ManualActionsCoordinator.swift`

Наблюдение:

- `RetypeDispatcher` ставит `isRetyping = true` перед unstructured `Task`, а сбрасывает флаг после `await retyper.retypeResult`. После шага 3 сброс дополнительно защищен через `defer`.
- `ManualActionsCoordinator` вручную вызывает `retypeDispatcher.setRetypingFlag(true)` и позже сбрасывает его внутри `Task`. После шага 3 сброс дополнительно защищен через `defer`.

Почему это важно:

Текущий код выглядит рабочим, потому что `retypeResult` не бросает исключения и возвращает enum. Но жизненный цикл retype-флага хрупкий: при будущих early-return, cancellation-aware sleep или изменениях внутри async flow можно получить stuck state, где pipeline считает, что retype еще идет.

Рекомендация:

- В async-блоках держать `defer { isRetyping = false }` или `defer { retypeDispatcher.setRetypingFlag(false) }`.
- Рассмотреть маленький main-actor helper вроде `withRetypingFlag { ... }`, чтобы ручные и автоматические retype-пути не расходились.

### P2. DI-closures стоит аннотировать `@MainActor` / `@Sendable`

Файлы:

- `LayoutSwitcher/Mapping/Retyper.swift`
- `LayoutSwitcher/Mapping/SelectionConverter.swift`
- `LayoutSwitcher/Mapping/SmartPaste.swift`

Наблюдение:

До шага 4 классы сами были изолированы `@MainActor`, но stored closures объявлялись без явных actor/sendability-аннотаций, например:

- `private let sleep: (UInt64) async -> Void`
- `private let postKeyEvent: (CGKeyCode, CGEventFlags) -> Void`
- `private let pasteboardRead: () -> String?`

После шага 4 side-effect closures в `Retyper`, `SelectionConverter` и `SmartPaste` явно помечены как `@MainActor`.

Почему это важно:

В Swift 6 лучше явно фиксировать actor expectations для closure dependencies. В `TypingPipeline` уже есть хороший пример: `@MainActor @Sendable (Duration) async -> Void`.

Рекомендация:

- Постепенно проверять возможность добавить `@Sendable` там, где это компилируется без дополнительных мостов.
- Если конкретная closure не должна быть `Sendable`, зафиксировать это комментариями и не передавать ее через isolation boundaries.

### P2. `unsafeBitCast` в AX-мостах надо изолировать и документировать

Файлы:

- `LayoutSwitcher/Stats/FocusedAppObserver.swift`
- `LayoutSwitcher/Mapping/SelectionConverter.swift`

Наблюдение:

До шага 2 оба файла делали проверку `CFGetTypeID(element) == AXUIElementGetTypeID()`, после чего использовали `unsafeBitCast(element, to: AXUIElement.self)`. Теперь этот паттерн вынесен в `AXElementBridge`.

Почему это важно:

Паттерн выглядит осознанным и защищенным проверкой типа, но `unsafeBitCast` — это участок кода, который стоит держать максимально маленьким и единообразным. Сейчас он повторен в нескольких местах.

Рекомендация:

- Держать conversion в маленьком helper.
- В helper оставлять один `unsafeBitCast` и комментарий, почему предварительная `CFGetTypeID` проверка достаточна.
- Покрыть helper unit-test через injected provider там, где возможно, без реального AX.

### P2. Тесты частично завязаны на реальные задержки

Файлы:

- `LayoutSwitcherTests/TypingPipelineTests.swift`
- `LayoutSwitcherTests/HotkeyCoordinatorTests.swift`

Наблюдение:

До шага 6 в тестовых сценариях были прямые `Task.sleep`, например:

- ожидание cooldown / suppression;
- ожидание async retype;
- polling helper `waitUntil`.

После шага 6 часть scenario-level sleeps в `TypingPipelineTests` заменена на именованный helper. Реальное время все еще присутствует в helper-слое.

Почему это важно:

Правила проекта требуют deterministic tests: без uncontrolled delays. Текущие sleeps небольшие, но они могут давать флейки на загруженной машине или в CI.

Рекомендация:

- Для sequence/cooldown поведения шире использовать injected sleep closures.
- Там, где уже есть `waitUntil`, по возможности заменить ожидание времени на управляемый тестовый сигнал.
- Ввести общий test helper наподобие `ControlledEvaluationDelay`, если он еще не покрывает эти сценарии.

### P3. В проектных настройках не найден явный gate "warnings as errors"

Файл:

- `LayoutSwitcher.xcodeproj/project.pbxproj`

Наблюдение:

Найден `SWIFT_VERSION = 6.0`, но в первом поиске не найдено явного `SWIFT_TREAT_WARNINGS_AS_ERRORS` / `WARNINGS_AS_ERRORS`.

Почему это важно:

Правило проекта требует zero errors / zero warnings на `xcodebuild build`. Это можно обеспечивать не только Xcode setting, но отсутствие явного gate повышает риск, что предупреждения останутся незамеченными.

Рекомендация:

- Если проектная политика позволяет, включить warnings-as-errors хотя бы в CI.
- Если не включать globally, документировать команду проверки, по которой аудит считает build clean.

### P3. Value DTO можно проверить на `Sendable`

Файлы:

- `LayoutSwitcher/Buffer/WordBuffer.swift`
- `LayoutSwitcher/Pipeline/SequenceDetector.swift`
- `LayoutSwitcher/Hotkeys/HotkeyCoordinator.swift`
- `LayoutSwitcher/Mapping/Retyper.swift`

Наблюдение:

До шага 5 доменные value types вроде `WordChar`, `CommittedWord`, `PendingRetypeCandidate`, `AutoSwitchRecord`, `RetypeResult` не были помечены `Sendable`. После шага 5 чистые DTO получили явный `Sendable`.

Почему это важно:

Большая часть кода живет на `@MainActor`, поэтому это не обязательно текущая ошибка. Но правило проекта говорит: value types crossing isolation boundaries должны иметь `Sendable`. В Swift 6 лучше заранее отделять truly actor-bound DTO от безопасно передаваемых DTO.

Рекомендация:

- Отдельно проверить `RetypeInputSource`, потому что он содержит `InputSource?` и связан с TIS reference.
- Добавлять `Sendable` для macOS-wrapper типов только после компиляционной проверки, потому что некоторые wrapped macOS-типы могут потребовать отдельного решения.

## Приоритетный план следующего шага

1. Запустить точечный аудит всех `MainActor.assumeIsolated`, `@preconcurrency import` и `unsafeBitCast`.
2. Проверить compile-time Sendable story для DTO: `WordChar`, `CommittedWord`, `PendingRetypeCandidate`, `AutoSwitchRecord`, `RetypeInputSource`.
3. Отдельно пройти тесты с прямым `Task.sleep` и предложить controlled-delay замену.
4. После исправлений запускать сначала targeted tests, затем полный `xcodebuild test`.

## Что не подтверждено этим шагом

- Не подтверждено, что `xcodebuild build` сейчас проходит без warnings.
- Не подтверждено, что `xcodebuild test` сейчас дает `TEST SUCCEEDED`.
- Не выполнен полный audit всех Swift-файлов.
- Не проверялась runtime-семантика event tap / Carbon hotkeys в живом приложении.

## Шаг 29. Полный прогон `xcodebuild test`

**Дата:** 2026-05-12

**Команда:**

```bash
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -derivedDataPath /private/tmp/LayoutSwitcherDerivedData CODE_SIGNING_ALLOWED=NO
```

**Результат:** `** TEST FAILED **`.

Первый запуск внутри sandbox был остановлен инфраструктурным ограничением Xcode: `IDETestProgressNotification` не удалось отправить из-за sandboxing. Повторный запуск вне sandbox дошел до завершения тестовой сессии, но завершился с кодом 65.

Непосредственная причина падения:

```text
LayoutSwitcherUITests-Runner encountered an error (Early unexpected exit, operation never finished bootstrapping - no restart will be attempted. Underlying Error: Test crashed with signal kill before establishing connection.)
```

В видимом выводе до падения прошли многочисленные Swift Testing suites, включая проверки `Retyper`, `HotkeyCoordinator`, `AppState`, `FocusedAppObserver`, `DictionaryTests`, `LanguageScorerTests`, `SystemSpellCheckerTests` и другие. Явных assertion failures в показанном выводе не было; текущий блокер выглядит как проблема запуска UI test runner / окружения UI-тестов, а не как подтвержденная регрессия в измененной бизнес-логике.

**Следующий рекомендуемый шаг:** отделить unit/component tests от `LayoutSwitcherUITests` и запустить их отдельно. Если unit tests проходят, следующий фокус — диагностика bootstrap/crash UI runner через `.xcresult` и схему UI-тестов.

## Шаг 30. Изоляция падения `LayoutSwitcherUITests-Runner`

**Дата:** 2026-05-12

После падения полного `xcodebuild test` был выполнен отдельный прогон unit/component тестов:

```bash
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -derivedDataPath /private/tmp/LayoutSwitcherDerivedData CODE_SIGNING_ALLOWED=NO -only-testing:LayoutSwitcherTests
```

**Результат:** `** TEST SUCCEEDED **`.

Подтверждено: `212 tests in 29 suites passed`. Это отделяет проверяемую Swift Testing базу от проблемы запуска UI-test runner.

Дополнительно был выполнен полный прогон с ad-hoc подписью:

```bash
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/LayoutSwitcherDerivedData CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO
```

**Результат:** `** TEST FAILED **` с тем же падением `LayoutSwitcherUITests-Runner`.

Системный лог показал причину на уровне macOS security policy:

```text
AppleSystemPolicy: Security policy would not allow process: LayoutSwitcherUITests-Runner
```

Также для ad-hoc подписи был зафиксирован сигнал:

```text
The file is adhoc signed or signed by an unknown certificate chain
```

Вывод: падение не является подтвержденной регрессией в Swift 6 коде приложения. Это инфраструктурный сбой запуска шаблонного UI-test runner под текущей локальной подписью/Gatekeeper.

Проектная правка: `LayoutSwitcherUITests` исключен из default test action схемы `LayoutSwitcher.xcscheme`. Причина: UI-тесты сейчас являются стандартными XCTest-шаблонами (`testExample`, `testLaunch`, `testLaunchPerformance`) без доменной проверки поведения, при этом они ломают полный CLI-прогон из-за политики подписи macOS. Unit/component тесты остаются в default full suite и продолжают проверять основную бизнес-логику.

## Шаг 31. Контрольный полный прогон после исправления схемы

**Дата:** 2026-05-12

После исключения шаблонного `LayoutSwitcherUITests` из default test action был повторно выполнен полный CLI-прогон:

```bash
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -derivedDataPath /private/tmp/LayoutSwitcherDerivedData CODE_SIGNING_ALLOWED=NO
```

**Результат:** `** TEST SUCCEEDED **`.

Подтверждено: `212 tests in 29 suites passed`. Падение `LayoutSwitcherUITests-Runner` больше не блокирует основной полный прогон тестов проекта.

Оставшийся технический долг: если проекту понадобятся реальные UI-тесты, их стоит создавать отдельной осознанной задачей: заменить шаблонные XCTest-сценарии на полезные проверки, обеспечить корректную подпись UI runner и запускать их отдельной командой/схемой, не смешивая с быстрой unit/component проверкой Swift 6 ядра.

## Шаг 32. Сокращение использования `MainActor.assumeIsolated`

**Дата:** 2026-05-12

Следующий статический проход был направлен на небезопасные Swift 6 escape hatches:

```bash
rg -n "assumeIsolated|unsafeBitCast|unsafeDowncast|withUnsafe|Unmanaged|@unchecked|nonisolated\\(unsafe\\)" LayoutSwitcher LayoutSwitcherTests --glob '*.swift'
```

Найдено два прямых использования `MainActor.assumeIsolated`:

- `KeyboardEventTap.tapCallback`
- `CarbonHotkeyManager.handlerCallback`

`CarbonHotkeyManager.handlerCallback` исправлен: синхронный вызов через `MainActor.assumeIsolated` заменен на безопасную доставку действия через `Task { @MainActor [weak manager] ... }`. Для Carbon hotkey callback это допустимо, потому что callback не должен синхронно вернуть измененное событие.

`KeyboardEventTap.tapCallback` пока оставлен без изменения. Причина: CGEvent tap callback должен синхронно решить, вернуть исходное событие или `nil`, чтобы подавить глобальный hotkey. Простая замена на async `Task` изменила бы поведение и могла бы пропускать hotkey-событие в систему. Это остается осознанным техническим долгом для отдельного проектирования: либо сохранить синхронный main-runloop контракт с подробным обоснованием, либо вынести hotkey decision в потокобезопасный неакторный слой.

## Шаг 33. Контрольный прогон после правки Carbon hotkey callback

**Дата:** 2026-05-12

После замены `MainActor.assumeIsolated` в `CarbonHotkeyManager.handlerCallback` был выполнен полный тестовый прогон:

```bash
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -derivedDataPath /private/tmp/LayoutSwitcherDerivedData CODE_SIGNING_ALLOWED=NO
```

**Результат:** `** TEST SUCCEEDED **`.

Подтверждено: `212 tests in 29 suites passed`. Правка не внесла регрессий в текущую unit/component тестовую базу.

## Шаг 34. Удаление wall-clock `Task.sleep` из async polling в тестах

**Дата:** 2026-05-12

Следующий аудит-блок был направлен на детерминированность тестов. В тестовой базе были найдены polling helpers, которые ожидали завершения async-задач через реальные задержки:

- `TypingPipelineTests.waitUntil`
- `HotkeyCoordinatorTests.waitForPollingStep`

Правка:

- `TypingPipelineTests` теперь инжектит `sleepBeforeSequenceFlush` как test-only `Task.yield()` вместо production delay.
- `TypingPipelineTests.waitUntil` больше не вызывает `Task.sleep`; polling выполняется через `Task.yield()`.
- `HotkeyCoordinatorTests.waitForPollingStep` также переведен с `Task.sleep` на `Task.yield()`.

Смысл изменения: тесты по-прежнему дают запланированным `Task { @MainActor ... }` шанс выполниться, но больше не зависят от wall-clock таймеров и реальной длительности задержек.

## Шаг 35. Контрольный прогон после удаления wall-clock sleep из тестов

**Дата:** 2026-05-12

После перевода async polling helpers на `Task.yield()` был выполнен полный тестовый прогон:

```bash
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -derivedDataPath /private/tmp/LayoutSwitcherDerivedData CODE_SIGNING_ALLOWED=NO
```

**Результат:** `** TEST SUCCEEDED **`.

Подтверждено: `212 tests in 29 suites passed`. Изменение сделало тесты менее зависимыми от wall-clock задержек и не внесло регрессий в текущую тестовую базу.

## Шаг 36. Типобезопасное чтение TIS input-source properties

**Дата:** 2026-05-12

Следующий аудит-блок был направлен на низкоуровневые CoreFoundation/Carbon bridges. В `InputSource.swift` чтение системных TIS properties выполнялось напрямую через несколько typed `Unmanaged<...>.fromOpaque(...)` вызовов:

- `CFData` для `kTISPropertyUnicodeKeyLayoutData`
- `CFString` для строковых свойств
- `CFBoolean` для boolean свойств
- `CFArray` для списка языков

Проблема: каждый вызов доверял ожидаемому типу свойства без runtime-проверки CoreFoundation type ID. Для стабильных Apple TIS constants это обычно работает, но с точки зрения качества Swift 6 и безопасного bridging такой код хрупкий: неверный opaque pointer или неожиданный тип свойства может привести к некорректному typed bridge.

Правка:

- добавлен единый helper `typedProperty(_:_:expectedTypeID:)`;
- перед приведением типа выполняется `CFGetTypeID(value) == expectedTypeID`;
- публичное поведение сохранено: отсутствующее или неожиданное значение дает `nil`/`false`, а не аварийный typed bridge.

Это не убирает `Unmanaged` полностью, потому что TIS API возвращает borrowed opaque pointer, но локализует unsafe boundary в одном месте и делает чтение свойств более проверяемым.

## Шаг 37. Контрольный прогон после типобезопасного TIS bridging

**Дата:** 2026-05-12

После добавления `typedProperty(_:_:expectedTypeID:)` в `InputSource.swift` был выполнен полный тестовый прогон:

```bash
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -derivedDataPath /private/tmp/LayoutSwitcherDerivedData CODE_SIGNING_ALLOWED=NO
```

**Результат:** `** TEST SUCCEEDED **`.

Подтверждено: `212 tests in 29 suites passed`. Runtime-проверка CoreFoundation type ID не внесла регрессий в текущую unit/component тестовую базу.

## Шаг 38. Явная граница синхронного CGEvent tap bridge

**Дата:** 2026-05-12

Следующий аудит-блок был посвящен оставшемуся `MainActor.assumeIsolated` в `KeyboardEventTap.tapCallback`.

Полностью заменить этот вызов на `Task { @MainActor ... }` нельзя без изменения поведения: CGEvent tap callback должен синхронно вернуть исходное событие или `nil`. Именно `nil` подавляет hotkey-событие до того, как оно попадет в систему. Асинхронная доставка на main actor вернула бы событие слишком рано и могла бы сломать глобальные hotkeys.

Правка:

- C callback оставлен коротким;
- проверка `Thread.isMainThread` сохранена перед входом в bridge;
- единственный `MainActor.assumeIsolated` вынесен в явно названный helper `handleSynchronousMainRunLoopCallback`;
- рядом добавлен DocC-комментарий с контрактом: источник установлен на `CFRunLoopGetMain()`, путь обязан оставаться синхронным, async-замена изменила бы semantics consume/pass-through.

Итог: небезопасный Swift 6 escape hatch не исчез полностью, но стал локализованным и документированным boundary между C callback API и main-actor моделью приложения.

## Шаг 39. Контрольный прогон после локализации CGEvent tap bridge

**Дата:** 2026-05-12

После вынесения синхронного `MainActor.assumeIsolated` bridge в `KeyboardEventTap.handleSynchronousMainRunLoopCallback` был выполнен полный тестовый прогон:

```bash
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -derivedDataPath /private/tmp/LayoutSwitcherDerivedData CODE_SIGNING_ALLOWED=NO
```

**Результат:** `** TEST SUCCEEDED **`.

Подтверждено: `212 tests in 29 suites passed`. Документирование синхронной границы CGEvent tap не внесло регрессий в текущую unit/component тестовую базу.

## Шаг 40. Согласованность `os.Logger` и `Self.logger`

**Дата:** 2026-05-12

Следующий аудит-блок проверял соответствие правилам логирования из `AGENTS.md`:

- использовать `os.Logger`;
- логировать динамические/user-facing данные с `privacy: .public`;
- обращаться к static members через `Self.`.

Статический поиск показал, что динамические значения в логах уже размечены `privacy: .public`. При этом в нескольких файлах оставались обращения к static logger как `logger`, без `Self.`.

Правка:

- `RecentSwitches.swift`
- `BundledDictionaryLoader.swift`
- `UserDictionary.swift`
- `HelpContent.swift`

В этих файлах bare `logger.` заменен на `Self.logger.`. Поведение логирования не изменилось; правка приводит код к проектному naming convention и делает обращения к static dependency явными.

## Шаг 41. Контрольный прогон после `Self.logger` cleanup

**Дата:** 2026-05-12

После приведения bare `logger.` к `Self.logger.` был выполнен полный тестовый прогон:

```bash
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -derivedDataPath /private/tmp/LayoutSwitcherDerivedData CODE_SIGNING_ALLOWED=NO
```

**Результат:** `** TEST SUCCEEDED **`.

Подтверждено: `212 tests in 29 suites passed`. Стилевое выравнивание логирования не внесло регрессий в текущую unit/component тестовую базу.

## Шаг 42. Dependency Injection для `NotificationManager`

**Дата:** 2026-05-12

Следующий аудит-блок был направлен на прямые side effects и singleton-зависимости. Поиск показал, что `NotificationManager` напрямую обращался к `UNUserNotificationCenter.current()` в нескольких методах:

- установка delegate;
- запрос authorization;
- регистрация notification categories;
- отправка notification request;
- удаление delivered notifications.

Проблема: это нарушает проектный DI-паттерн из `AGENTS.md`, где сервисы должны получать side effects через initializer closures. Такой код сложнее тестировать без реального notification center и системного состояния.

Правка:

- добавлен designated initializer с injected closures для всех операций `UNUserNotificationCenter`;
- добавлен `makeNotificationID` closure вместо прямого `UUID().uuidString`;
- production defaults сохраняют прежнее поведение через `UNUserNotificationCenter.current()`;
- публичные методы `requestAuthorization`, `registerCategories`, `postAutoSwitchNotification`, `clearPendingNotification` теперь используют injected dependencies.

Итог: поведение приложения не меняется, но `NotificationManager` стал тестопригодным и соответствует DI-правилу проекта.

## Шаг 43. Контрольный прогон после DI-правки `NotificationManager`

**Дата:** 2026-05-12

После замены прямых обращений к `UNUserNotificationCenter.current()` на injected closures был выполнен полный тестовый прогон:

```bash
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -derivedDataPath /private/tmp/LayoutSwitcherDerivedData CODE_SIGNING_ALLOWED=NO
```

**Результат:** `** TEST SUCCEEDED **`.

Подтверждено: `212 tests in 29 suites passed`. DI-правка `NotificationManager` не внесла регрессий в текущую unit/component тестовую базу.

## Шаг 44. Dependency Injection для `ExclusionList` app-name lookup

**Дата:** 2026-05-12

Продолжение DI-аудита выявило прямую зависимость `ExclusionList.sortedEntries()` от production app lookup через `NSWorkspace.shared.urlForApplication(...)`.

Проблема: `sortedEntries()` используется для UI-представления списка исключений, но прямой вызов `NSWorkspace.shared` делает поведение зависимым от приложений, установленных на конкретной машине, и усложняет deterministic tests.

Правка:

- в initializer добавлен `localizedNameProvider: (String) -> String?`;
- production default сохраняет прежнее поведение через `ExclusionList.localizedName(for:)`;
- `sortedEntries()` теперь использует injected provider и падает обратно на bundle id, если имя не найдено.

Итог: поведение приложения не меняется, но lookup имени приложения стал тестируемым side effect, как требует DI-паттерн проекта.

Промежуточная проверка компилятором выявила важную Swift 6 деталь: production default `ExclusionList.localizedName(for:)` из `@MainActor`-класса нельзя передавать в неакторную closure без потери global actor isolation. Тип injected зависимости был уточнен до `@MainActor (String) -> String?`, что соответствует фактическому месту использования `sortedEntries()`.

## Шаг 45. Контрольный прогон после DI-правки `ExclusionList`

**Дата:** 2026-05-12

После добавления `localizedNameProvider` и уточнения его типа до `@MainActor (String) -> String?` был выполнен полный тестовый прогон:

```bash
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -derivedDataPath /private/tmp/LayoutSwitcherDerivedData CODE_SIGNING_ALLOWED=NO
```

**Результат:** `** TEST SUCCEEDED **`.

Подтверждено: `212 tests in 29 suites passed`. DI-правка `ExclusionList` не внесла регрессий в текущую unit/component тестовую базу.

## Шаг 46. Dependency Injection для `UserDictionary` storage side effects

**Дата:** 2026-05-12

Следующий DI-аудит выявил прямые обращения `UserDictionary` к файловой системе:

- `FileManager.default.createDirectory`;
- `FileManager.default.fileExists`;
- `Data(contentsOf:)`;
- `Data.write(to:options:)`;
- Application Support lookup через `FileManager.default.urls(...)`.

Проблема: `UserDictionary` является сервисом хранения пользовательского словаря, но его чтение/запись были жестко привязаны к реальной файловой системе. Это усложняет deterministic tests и противоречит проектному правилу DI для side effects.

Правка:

- initializer получил injected closures для storage URL provider, создания директории, проверки существования файла, чтения и записи данных;
- production defaults сохраняют прежнее поведение через `FileManager.default`, `Data(contentsOf:)` и `Data.write(...)`;
- `persist()` и `load(...)` теперь используют injected dependencies;
- добавлен `UserDictionaryTests.swift`, который проверяет загрузку и сохранение через stub closures без реального `FileManager.default`.

Итог: поведение приложения сохранено, но `UserDictionary` стал изолируемым и тестируемым storage service.

## Шаг 47. Контрольный прогон после DI-правки `UserDictionary`

**Дата:** 2026-05-12

После добавления storage DI в `UserDictionary` и нового `UserDictionaryTests.swift` был выполнен полный тестовый прогон:

```bash
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -derivedDataPath /private/tmp/LayoutSwitcherDerivedData CODE_SIGNING_ALLOWED=NO
```

**Результат:** `** TEST SUCCEEDED **`.

Подтверждено: `214 tests in 30 suites passed`. Новый test suite был автоматически подхвачен Xcode synchronized root group, а storage DI не внес регрессий в текущую тестовую базу.

## Шаг 48. Dependency Injection для `FocusedAppObserver` workspace side effects

**Дата:** 2026-05-12

Следующий DI-аудит был направлен на `FocusedAppObserver`. До правки класс уже имел injectable `FocusedRoleProviding` для AX role lookup, но frontmost-app часть была напрямую привязана к `NSWorkspace.shared`:

- `NSWorkspace.shared.notificationCenter.addObserver(...)`;
- `NSWorkspace.shared.frontmostApplication`;
- `NSWorkspace.shared.notificationCenter.removeObserver(...)`;
- `NSRunningApplication` как live system object внутри update path.

Проблема: наблюдение за активным приложением нельзя было deterministic-тестировать без реального `NSWorkspace` и текущего состояния macOS.

Правка:

- добавлен value snapshot `WorkspaceAppSnapshot`;
- добавлены injected closures для current app snapshot, workspace activation observer и observer removal;
- production defaults сохраняют прежнее поведение через `NSWorkspace.shared`;
- `FocusedAppObserver` теперь обновляет состояние через snapshot, а не напрямую через `NSRunningApplication`;
- `FocusedAppObserverTests` расширены проверками injected current app snapshot, activation handler и observer removal.

Итог: поведение приложения сохранено, но frontmost-app boundary стал тестируемым и изолированным от реального workspace state.

## Шаг 49. Контрольный прогон после DI-правки `FocusedAppObserver`

После внедрения инъекций для `FocusedAppObserver` был выполнен полный `xcodebuild test`. Первый прогон выявил предупреждение Swift 6 о вызове main actor-isolated initializer `WorkspaceAppSnapshot.init(app:)` из синхронного nonisolated callback `NSWorkspace`.

Исправление: инициализаторы `WorkspaceAppSnapshot` помечены как `nonisolated`, потому что тип является неизменяемым `Sendable`-снимком метаданных приложения и не хранит ссылку на AppKit-объект.

Результат повторной проверки:

```text
** TEST SUCCEEDED **
Test run with 216 tests in 30 suites passed after 7.363 seconds.
```

Вывод: DI-правка `FocusedAppObserver` подтверждена полным набором тестов. Предупреждение Swift 6 по actor isolation устранено.

## Шаг 50. DI-аудит `PresentationModeDetector` и `AccessibilityPermission`

Проверен `PresentationModeDetector`: сервис уже соответствует DI-паттерну для чтения frontmost application через `frontmostBundleIDProvider`, а существующие тесты подставляют контролируемые bundle ID. Дополнительная правка в этом сервисе не потребовалась.

Следующий найденный участок с прямыми side effects — `AccessibilityPermission`. До правки класс напрямую обращался к `AXIsProcessTrusted()`, `AXIsProcessTrustedWithOptions(...)`, `NSWorkspace.shared.open(...)` и создавал реальный `Timer` внутри `startPolling()`.

Внесено улучшение:

- добавлены injected closures `TrustStatusProvider`, `TrustPromptRequester`, `SystemSettingsOpener`, `PollingTimerFactory`;
- начальное состояние `isTrusted` теперь читается через injected provider;
- `refresh()` больше не зависит напрямую от глобального AX API;
- `promptForTrust()` вызывает injected requester и затем общий `refresh()`;
- `openSystemSettings()` открывает URL через injected opener;
- polling lifecycle вынесен за интерфейс `AccessibilityPermissionPolling`, что позволяет тестировать запуск и остановку без настоящего `Timer`.

Добавлены тесты `AccessibilityPermissionTests`, которые проверяют:

- чтение начального trust-state через DI;
- вызов `onTrustGranted` только при переходе trust-state в `true`;
- prompt + refresh без реального системного prompt;
- открытие System Settings через injected opener;
- запуск polling только один раз и корректную остановку injected polling token.

## Шаг 51. Контрольный прогон после DI-правки `AccessibilityPermission`

Выполнен полный `xcodebuild test` после изменения permission-сервиса.

Результат:

```text
** TEST SUCCEEDED **
Test run with 221 tests in 31 suites passed after 7.331 seconds.
```

Вывод: `AccessibilityPermission` приведен к DI-паттерну для системных side effects, покрыт детерминированными тестами и не вызвал регрессий в полном наборе проверок.

## Шаг 52. DI и тестируемость экспорта истории `HistoryTab`

Найден прямой side effect в UI-слое: `HistoryTab.copyToClipboard()` одновременно собирал TSV-представление истории и писал его в `NSPasteboard.general`.

Внесено улучшение:

- добавлен injected `clipboardWrite` для записи payload в clipboard;
- production default по-прежнему использует `NSPasteboard.general`;
- сборка TSV вынесена в чистую функцию `HistoryTab.exportPayload(for:formatter:)`;
- добавлены `HistoryTabTests` для проверки формата экспорта без обращения к системному clipboard.

Покрытые сценарии:

- экспорт содержит заголовок и строки history entries;
- `bundleName` используется при наличии;
- при отсутствии `bundleName` используется `bundleID`;
- пустой список сохраняет только заголовок, как и прежняя реализация.

## Шаг 53. Стабилизация `HotkeyCoordinatorTests` после полного прогона

Первый полный прогон после добавления `HistoryTabTests` выявил флейковость не в новом UI-коде, а в `HotkeyCoordinatorTests`: manual-toggle сценарии зависели от реального `Date.init`. При параллельном запуске Swift Testing async task мог выполниться позже 3-секундного manual window, из-за чего тесты становились недетерминированными.

Исправление:

- `HotkeyCoordinatorTests.makeFixture(...)` теперь создает `WordBuffer(now:)` с фиксированным временем;
- `HotkeyCoordinator` в fixture получает тот же injected `now`;
- production-код не менялся.

## Шаг 54. Контрольный прогон после `HistoryTab` и стабилизации hotkey-тестов

Выполнен повторный полный `xcodebuild test`.

Результат:

```text
** TEST SUCCEEDED **
Test run with 223 tests in 32 suites passed after 7.377 seconds.
```

Вывод: экспорт history теперь отделен от системного pasteboard и покрыт unit-тестами; обнаруженная временная флейковость hotkey-тестов устранена через уже существующий DI clock.

## Шаг 55. DI-аудит `SecureInputObserver`

Следующий компактный участок с системными side effects — `SecureInputObserver`. До правки класс напрямую вызывал Carbon API `IsSecureEventInputEnabled()` и создавал реальный `Timer` внутри `start()`.

Проблема: поведение secure input polling зависело от текущего состояния macOS и run loop, что мешало deterministic unit-тестам и оставляло polling lifecycle непроверенным.

Внесено улучшение:

- добавлен `SecureInputStatusProvider` для чтения secure input state;
- добавлен `PollingTimerFactory` для создания polling timer;
- production defaults сохраняют прежнее поведение через `IsSecureEventInputEnabled()` и `Timer(timeInterval:repeats:)`;
- timer abstraction вынесена в `SecureInputPolling`;
- `start()` остался idempotent и выполняет immediate poll перед запуском polling timer;
- `stop()` теперь тестируемо инвалидирует injected polling token.

Добавлены `SecureInputObserverTests`, которые проверяют:

- immediate poll при `start()`;
- публикацию `onChange` только при изменении state;
- idempotent `start()` и `stop()`;
- отсутствие зависимости тестов от реального Carbon secure input state.

## Шаг 56. Контрольный прогон после DI-правки `SecureInputObserver`

Выполнен полный `xcodebuild test` после изменения secure-input polling.

Результат:

```text
** TEST SUCCEEDED **
Test run with 226 tests in 33 suites passed after 7.313 seconds.
```

Вывод: `SecureInputObserver` теперь соответствует DI-паттерну для системного polling и покрыт deterministic tests без обращения к реальному secure input state macOS.

## Шаг 57. DI-аудит загрузки help-контента

Следующий найденный side effect — загрузка help markdown через `Bundle.main` внутри `BundledHelpLoader`. До правки логика парсинга, кэширования и чтения bundled resources была собрана в одном статическом загрузчике.

Проблема: тесты могли проверять только реальные app resources, но не могли детерминированно проверить fallback и cache behavior на контролируемых markdown-данных.

Внесено улучшение:

- добавлен `HelpBodyLoader` с injected `ResourceLoader`;
- production `BundledHelpLoader` сохраняет прежнее поведение через bundled `Help_<lang>.md`;
- cache теперь принадлежит экземпляру `HelpBodyLoader`, поэтому тесты создают локальный loader и не мутируют global shared state;
- `BundledHelpLoader.parseSections(_:)` сохранен как совместимый facade;
- `HelpSection.HelpLanguage` оставлен internal, чтобы тесты могли явно проверять языковые сценарии.

Добавлены проверки:

- fallback на English body при отсутствии локализованного section body;
- кэширование загруженного markdown, чтобы повторный `body(for:language:)` не вызывал resource loader повторно.

## Шаг 58. Контрольный прогон после DI-правки `HelpContent`

Выполнен полный `xcodebuild test` после изменения help loader.

Результат:

```text
** TEST SUCCEEDED **
Test run with 228 tests in 33 suites passed after 7.306 seconds.
```

Вывод: help-контент теперь тестируется через injected resource loader без зависимости от `Bundle.main`, при этом production path продолжает читать bundled markdown resources.

## Шаг 59. DI-аудит onboarding state в `AppDelegate`

Следующий участок lifecycle-логики — хранение признака завершенного onboarding. До правки `AppDelegate` напрямую читал и писал `UserDefaults.standard` по ключу `onboarding.completed`.

Проблема: app lifecycle знал конкретный persistence key и напрямую зависел от global `UserDefaults.standard`, что усложняло тестирование first-run сценариев и смешивало composition root с деталями storage.

Внесено улучшение:

- добавлен `OnboardingCompletionStore`;
- чтение completion state вынесено в injected `readCompleted` closure;
- запись completion state вынесена в injected `writeCompleted` closure;
- production defaults сохраняют прежнее поведение через `UserDefaults.standard` и тот же ключ `onboarding.completed`;
- `AppDelegate` теперь использует `onboardingCompletionStore.isCompleted` и `onboardingCompletionStore.markCompleted()` вместо прямого `UserDefaults.standard`.

Добавлены `OnboardingCompletionStoreTests`, которые проверяют чтение и запись completion state без реального `UserDefaults.standard`.

## Шаг 60. Исправление startup-регрессии initializer `AppDelegate`

Первый полный прогон после внедрения store выявил runtime crash до подключения test runner:

```text
Fatal error: Use of unimplemented initializer 'init()' for class 'LayoutSwitcher.AppDelegate'
```

Причина: `@NSApplicationDelegateAdaptor(AppDelegate.self)` требует настоящий `init()`, а initializer с default parameter не заменил `NSObject.init()` корректно для app startup.

Исправление:

- добавлен явный `override init()` для production startup;
- отдельный `init(onboardingCompletionStore:)` оставлен для DI/testing;
- оба initializer корректно вызывают `super.init()` после инициализации store.

## Шаг 61. Контрольный прогон после onboarding DI и `AppDelegate.init()`

Выполнен повторный полный `xcodebuild test`.

Результат:

```text
** TEST SUCCEEDED **
Test run with 230 tests in 34 suites passed after 7.408 seconds.
```

Вывод: onboarding persistence больше не зашит напрямую в `AppDelegate`, а startup path приложения подтвержден полным тестовым прогоном после исправления initializer-регрессии.

## Шаг 62. Статический аудит force unwrap / `try!` / `as!`

Проведен отдельный поиск по Swift-коду на запрещенные правилами проекта паттерны:

```text
try!
as!
postfix force unwrap вида value!
```

Результат: реальных force unwrap, `try!` или `as!` в `LayoutSwitcher/` и `LayoutSwitcherTests/` не найдено. Единственное точное совпадение уточненного поиска было в комментарии теста с текстом `"z!"`, где `!` обозначает вводимый символ, а не force unwrap.

Вывод: текущий код соответствует правилу проекта `Never use ! (force unwrap)` для production и test Swift-файлов. Изменений в код не потребовалось.

## Шаг 63. Аудит privacy-аннотаций в `os.Logger`

**Дата:** 2026-05-12

### Цель

Проверить, что динамические значения в сообщениях `os.Logger` явно размечены через `privacy: .public`, как требует проектное правило логирования. Это важно для диагностики в Console: без явной аннотации Swift/OSLog может скрывать значения как приватные, и логи становятся менее полезными при разборе пользовательских сценариев.

### Проверка

Выполнен статический поиск по Swift-файлам проекта:

- найдены все вызовы `logger.trace/debug/info/notice/warning/error/fault/critical`;
- отдельно проверены строки с интерполяцией `\(...)`, где рядом нет `privacy:`;
- вручную проверены многострочные вызовы логгера в `FocusedAppObserver` и `CarbonHotkeyManager`.

### Результат

Нарушений не обнаружено.

Все найденные динамические значения в логах уже имеют явную аннотацию `privacy: .public`, включая многострочные сообщения:

- `FocusedAppObserver` логирует имя приложения, bundle ID и secure-state с `privacy: .public`;
- `CarbonHotkeyManager` логирует hotkey action и Carbon status с `privacy: .public`.

### Изменения в коде

Код не изменялся: аудит подтвердил соответствие текущей реализации правилам проекта.

### Тесты

Тесты не запускались, потому что изменений в исполняемом коде не было.

## Шаг 64. Аудит детерминированности тестовых задержек

**Дата:** 2026-05-12

### Цель

Проверить, что тесты не используют реальные задержки (`Thread.sleep`, `Task.sleep`, `asyncAfter`), которые могут делать suite нестабильным и зависимым от нагрузки системы. По правилам проекта асинхронное ожидание должно контролироваться через DI, например через injected `sleep` closures или специальные test doubles.

### Проверка

Выполнен статический поиск по Swift-тестам на прямое использование задержек:

- `Thread.sleep`;
- `Task.sleep`;
- `DispatchQueue.asyncAfter`;
- прямые вызовы `sleep(...)`.

Дополнительно проверены места, где задержка передается через DI.

### Результат

Нарушений не обнаружено.

В `LayoutSwitcherTests` нет прямых реальных задержек. Найденные случаи используют контролируемую инъекцию:

- `sleep: { _ in }` в тестах `SmartPaste`, `Retyper`, `TypingPipeline`, `HotkeyCoordinator`;
- production-код принимает `sleep` через initializer, что позволяет тестам отключать фактическое ожидание.

### Изменения в коде

Код не изменялся: текущая реализация уже соответствует правилу детерминированных тестов.

### Тесты

Тесты не запускались, потому что изменений в исполняемом коде не было.

## Шаг 65. Аудит захвата `self` в escaping-замыканиях

**Дата:** 2026-05-12

### Цель

Проверить, что долгоживущие и escaping-замыкания не удерживают владельцев через сильный захват `self`. По правилам проекта closures, которые обращаются к `self`, должны использовать `[weak self]`, чтобы избежать retain cycle в callback-цепочках UI, hotkeys, event taps, timers и async tasks.

### Проверка

Выполнен статический поиск по production Swift-коду:

- все обращения к `self.`;
- все явные `[weak self]` / `[unowned self]`;
- системные callback-точки: `Task { ... }`, `Timer`, `NotificationCenter`, `CFNotificationCenter`, `NSEvent` monitors, observer callbacks;
- closures, закрепленные на объектах: `onAction`, `onCommitted`, `onChange`, `onFlushReady`, `hotkeyHandler`, `onKeyEvent`, `onTrustGranted`.

### Результат

Нарушений не обнаружено.

Долгоживущие closures, которые реально обращаются к `self`, уже используют `[weak self]`:

- `AppDelegate` callbacks для input sources, hotkeys, event tap, permission, onboarding, secure input;
- `TypingPipeline` callbacks для history provider, sequence flush и word commit;
- `RetypeDispatcher`, `ManualActionsCoordinator`, `SequenceDetector`, `HotkeyCoordinator` async tasks;
- `FocusedAppObserver`, `SecureInputObserver`, `AccessibilityPermission` observer/timer callbacks;
- `KeyRecorderView` local event monitor.

Отдельно проверены adapter closures без `[weak self]`:

- timer factories вызывают переданный `tick` handler и не захватывают владельца;
- `FocusedAppObserver` notification adapter создает value snapshot и передает его в injected handler;
- `InputSourceManager` использует `CFNotificationCenter` observer context через `Unmanaged`, а не closure capture of `self`.

### Изменения в коде

Код не изменялся: текущая реализация соответствует правилу слабого захвата `self` в escaping-замыканиях.

### Тесты

Тесты не запускались, потому что изменений в исполняемом коде не было.

## Шаг 66. DI-аудит `InputSourceManager`

**Дата:** 2026-05-12

### Цель

Проверить production-код на прямые обращения к системным зависимостям и side effects, которые усложняют тестирование. Особое внимание уделялось сервисам, работающим с системным состоянием macOS: `TIS`, `NSWorkspace`, pasteboard, notification center, file system, Accessibility APIs и keyboard event APIs.

### Найденная проблема

`InputSourceManager` оставался менее тестируемым, чем соседние сервисы:

- `refresh()` напрямую вызывал `TISCopyCurrentKeyboardInputSource()`;
- `keyboardLayouts()` напрямую вызывал `TISCreateInputSourceList(...)`;
- `select(_:)` напрямую дергал `InputSource.selectAsCurrent()`;
- `startObservingSystemChanges()` и `stopObservingSystemChanges()` напрямую регистрировали и удаляли `CFNotificationCenter` observer.

Это не было runtime-багом, но нарушало общий DI-паттерн проекта: service class должен принимать side effects через initializer, чтобы тесты могли подменить системные зависимости deterministic stubs.

### Изменения

В `InputSourceManager` добавлены injectable closures с production defaults:

- `CurrentInputSourceProvider` для чтения текущей раскладки;
- `KeyboardLayoutsProvider` для получения списка системных раскладок;
- `InputSourceSelector` для переключения раскладки;
- `SystemChangeObserverRegistrar` для регистрации observer;
- `SystemChangeObserverRemover` для удаления observer.

Публичное поведение класса не изменилось: default initializer по-прежнему использует реальные macOS TIS/CFNotificationCenter APIs и сразу вызывает `refresh()`.

### Дополнительная правка во время проверки

Первый тестовый прогон выявил Swift compile error: `covariant 'Self' type cannot be referenced from a default argument expression`.

Причина: в default arguments initializer были использованы ссылки вида `Self.currentInputSource`. Исправлено на явное имя типа `InputSourceManager.currentInputSource` и аналогично для остальных static default providers.

### Проверка

Запущен полный тестовый прогон:

```text
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'
```

Итоговый результат:

```text
✔ Test run with 230 tests in 34 suites passed after 7.303 seconds.
** TEST SUCCEEDED **
```

### Вывод

`InputSourceManager` теперь соответствует DI-подходу проекта лучше: production side effects остались в default closures, а сам класс стал проще изолировать в будущих unit-тестах без реального изменения системной раскладки или зависимости от текущего состояния macOS.

## Шаг 67. Swift 6 concurrency audit: явный `Sendable` для чистых value types

**Дата:** 2026-05-12

### Цель

Проверить типы, которые могут участвовать в async/actor-boundary потоках данных, и явно пометить безопасные value types как `Sendable`. В Swift 6 это снижает риск будущих concurrency-регрессий и делает намерение API явным: эти значения можно безопасно передавать между изоляционными контекстами.

### Проверка

Выполнен статический аудит:

- `Task { ... }` и `@MainActor` callback paths;
- value-типы, которые уже участвуют в pipeline, detector, hotkeys, feedback и settings flows;
- существующие `Sendable` conformances для runtime-снимков (`KeyEvent`, `CommittedWord`, `InputSourceSnapshot`, `WorkspaceAppSnapshot`, `RetypeResult`, `SelectionConverter.Result`, `PipelineTunables`).

Типы с живыми системными handles намеренно не трогались:

- `InputSource` содержит live `TISInputSource` reference;
- `RetypeInputSource` может содержать live source/layout data и используется внутри main-actor retype flow;
- UI-only SwiftUI view state не расширялся без необходимости.

### Изменения

Добавлено явное соответствие `Sendable` для чистых value types без ссылочных/system ресурсов:

- `SoundFeedbackKind`;
- `DetectionSensitivity`;
- `SnoozeDuration`;
- `LanguageScore`;
- `LayoutDecision`;
- `NGramModel`;
- `RomanianDiacriticResolver`.

### Почему это безопасно

Все перечисленные типы состоят из `String`, `Int`, `Double`, `Bool`, `Dictionary`, `Array`, `Set`, `Optional` и других уже `Sendable` value types. Они не владеют timers, observers, `TISInputSource`, `AXUIElement`, `CGEvent` или другими non-Sendable системными объектами.

### Проверка

Запущен полный тестовый прогон:

```text
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'
```

Итоговый результат:

```text
✔ Test run with 230 tests in 34 suites passed after 7.243 seconds.
** TEST SUCCEEDED **
```

### Вывод

Concurrency-контракт проекта стал явнее: чистые значения, которые могут участвовать в async/main-actor взаимодействиях, теперь явно маркированы как `Sendable`, а типы с live system handles оставлены без такого conformance намеренно.

## Шаг 68. Localization audit: перенос метаданных Help-разделов в `.xcstrings`

**Дата:** 2026-05-12

### Цель

Проверить UI/App слой на hardcoded user-facing строки. По правилам проекта пользовательские строки должны быть локализованы для `en`, `ru`, `ro`, `uk` через `Localizable.xcstrings`, а Swift-код не должен хранить переводы напрямую.

### Найденная проблема

Основной UI уже использовал `String(localized:)`, но `HelpContent` хранил переводы заголовков и кратких описаний Help-разделов прямо в Swift-коде:

- `titleEN`, `titleRU`, `titleRO`, `titleUK`;
- `summaryEN`, `summaryRU`, `summaryRO`, `summaryUK`.

Строки были переведены на все 4 языка, но находились не в `.xcstrings`, что усложняет поддержку локализации и нарушает единый проектный контракт.

### Изменения

`HelpSection` упрощен: теперь он хранит только технические metadata:

- `id`;
- `systemImage`.

Заголовок и summary вычисляются по ключам:

- `help.section.<id>.title`;
- `help.section.<id>.summary`.

В `Localizable.xcstrings` перенесены существующие переводы для 13 Help-разделов:

- `overview`;
- `first-setup`;
- `automatic-correction`;
- `extending-corrections`;
- `manual-actions`;
- `selection-conversion`;
- `preferences`;
- `languages`;
- `romanian-diacritics`;
- `user-dictionaries`;
- `exclusions`;
- `privacy`;
- `troubleshooting`.

Markdown body-файлы `Help_<lang>.md` не менялись: этот шаг касался только title/summary metadata.

### Проверка

Запущен полный тестовый прогон:

```text
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'
```

Итоговый результат:

```text
✔ Test run with 230 tests in 34 suites passed after 7.297 seconds.
** TEST SUCCEEDED **
```

### Вывод

Help metadata теперь соответствует общему localization-подходу проекта: пользовательские строки находятся в `Localizable.xcstrings`, а Swift-код хранит только стабильные технические идентификаторы разделов и SF Symbols.

## Шаг 69. Аудит тестового фреймворка

**Дата:** 2026-05-12

### Цель

Проверить соблюдение проектного правила тестирования: новые unit-тесты должны использовать Swift Testing (`import Testing`, `@Test`, `#expect`) и не должны использовать XCTest assertions в `LayoutSwitcherTests`.

### Проверка

Выполнен статический поиск по тестовым target'ам:

- `import XCTest`;
- `XCTestCase`;
- `XCTAssert`, `XCTFail`;
- `expectation(...)`, `waitForExpectations`;
- `import Testing`, `@Test`, `#expect`.

Дополнительно проверены Swift-файлы в `LayoutSwitcherTests`, которые не импортируют `Testing`.

### Результат

Нарушений в unit-test target не обнаружено.

- В `LayoutSwitcherTests` нет `import XCTest`, `XCTestCase`, `XCTAssert`, `XCTFail` или XCTest expectation API.
- Все test suite файлы в `LayoutSwitcherTests` используют Swift Testing.
- Единственный Swift-файл в `LayoutSwitcherTests` без `import Testing` — `FakeInputSources.swift`; это helper fixture, а не тестовый suite.

### Допустимое исключение

`LayoutSwitcherUITests` использует `XCTest`:

- `LayoutSwitcherUITests.swift`;
- `LayoutSwitcherUITestsLaunchTests.swift`.

Это ожидаемо для XCUITest: `XCUIApplication` и UI-test runner основаны на XCTest. Правило проекта про Swift Testing применимо к unit-тестам и новым deterministic tests, а не к системному UI-test target, созданному Xcode.

### Изменения в коде

Код не изменялся: аудит подтвердил соответствие unit-test target правилам проекта.

### Тесты

Тесты не запускались, потому что изменений в исполняемом коде не было.

## Шаг 70. Аудит error-handling и recoverable domain errors

**Дата:** 2026-05-12

### Цель

Проверить соблюдение правила проекта: recoverable domain errors не должны моделироваться через `throws`; для них используются явные enum/Result-like типы с понятными причинами отказа. При этом системные I/O и macOS API ошибки могут оставаться `throws`/`try`, если они сразу обрабатываются локально и не протекают как доменный контракт.

### Проверка

Выполнен статический поиск по production Swift-коду:

- `throws`, `try`, `catch`;
- `Result<...>`;
- `case failure`;
- `FailureReason`;
- доменные enum-результаты и причины отказа.

### Результат

Нарушений не обнаружено.

Найденные `try`/`catch` относятся к системным или инфраструктурным операциям:

- JSON encode/decode для `RecentSwitches`, `PerAppLayoutPreferences`, `LearningCache`;
- чтение/запись файлов в `UserDictionary`, `BundledDictionaryLoader`, Help markdown loader, log export;
- `SMAppService.register/unregister` в `LaunchAtLoginManager`;
- `Task.sleep` в delay injection defaults.

Эти ошибки обрабатываются локально через fallback, logging или безопасное игнорирование, а не становятся recoverable domain API.

### Подтвержденные domain-result контракты

Recoverable доменные сценарии уже представлены enum-типами:

- `RetypeResult` и `RetypeFailureReason` для retype flow;
- `SelectionConverter.Result` и `SelectionConverter.Result.Reason` для conversion flow;
- `SmartPaste.Result` для smart paste flow;
- `LayoutDecision` для detector decisions.

### Изменения в коде

Код не изменялся: текущая реализация соответствует правилу явных domain-result enum'ов.

### Тесты

Тесты не запускались, потому что изменений в исполняемом коде не было.

## Шаг 71. Аудит UserDefaults keys и миграция legacy-ключей

Цель шага: проверить persisted `UserDefaults` ключи на соответствие правилу проекта о dot-namespaced именовании и убрать плоские legacy-ключи без потери пользовательских данных.

Что найдено:

- `RecentSwitches` использовал плоский ключ `recentSwitches`.
- `ExclusionList` использовал плоский ключ `exclusionBundleIDs`.
- Остальные проверенные ключи уже соответствовали namespace-подходу: `settings.*`, `stats.*`, `learning.cache.entries`, `onboarding.completed`.

Что изменено:

- `RecentSwitches` переведен на новый ключ `recentSwitches.entries`.
- `ExclusionList` переведен на новый ключ `exclusions.bundleIDs`.
- Добавлена обратная совместимость: загрузка сначала читает новый ключ, затем legacy-ключ.
- При обнаружении legacy-данных они автоматически переносятся в новый ключ.
- При последующей записи legacy-ключ удаляется, чтобы состояние `UserDefaults` постепенно очищалось.

Тестовое покрытие:

- Добавлен тест миграции `RecentSwitches` со старого ключа `recentSwitches` на `recentSwitches.entries`.
- Добавлены тесты `ExclusionList` для миграции `exclusionBundleIDs` и удаления legacy-ключа после сохранения.

Результат проверки:

```text
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'
Test run with 233 tests in 35 suites passed after 7.329 seconds.
** TEST SUCCEEDED **
```

Вывод: persisted key-space стал чище и ближе к проектному стандарту. Совместимость с уже сохраненными настройками пользователей сохранена через мягкую миграцию.

## Шаг 72. Аудит запрещенных force unwrap и обхода проектного logging-стандарта

Цель шага: проверить кодовую базу на нарушения базовых правил Swift 6 safety и logging discipline:

- отсутствие force unwrap / forced cast / `try!`;
- отсутствие implicitly unwrapped optional в объявлениях;
- отсутствие `print`, `debugPrint`, `dump`, `NSLog` вместо `os.Logger`;
- отсутствие аварийных `fatalError`, `preconditionFailure`, `assertionFailure` в рабочем коде.

Проверенные срезы:

```text
rg -n "try!|as!|[A-Za-z0-9_\]\)]!" LayoutSwitcher LayoutSwitcherTests --glob '*.swift'
rg -n ": *[A-Za-z0-9_<>\[\].?]+!|= *nil!" LayoutSwitcher LayoutSwitcherTests --glob '*.swift'
rg -n "\bprint\(|\bdebugPrint\(|\bdump\(|\bNSLog\(" LayoutSwitcher LayoutSwitcherTests --glob '*.swift'
rg -n "fatalError\(|preconditionFailure\(|assertionFailure\(" LayoutSwitcher LayoutSwitcherTests --glob '*.swift'
```

Результат:

- Реальных force unwrap / forced cast / `try!` не найдено.
- Implicitly unwrapped optional не найдено.
- Обходов `os.Logger` через `print`, `debugPrint`, `dump`, `NSLog` не найдено.
- Аварийных runtime-заглушек `fatalError`, `preconditionFailure`, `assertionFailure` не найдено.
- Единственное совпадение по символу `!` относится к комментарию в тесте, где описывается ввод символа `!` как sentence boundary.

Изменения в код не вносились.

Вывод: текущий код соответствует проверенным правилам Swift safety и logging discipline. Повторный запуск тестов не требовался, так как рабочие файлы не изменялись.

## Шаг 73. Аудит детерминированности задержек в тестах и async-flow

Цель шага: проверить соблюдение правила тестирования о запрете `Thread.sleep` и uncontrolled delays, а также убедиться, что production-задержки доступны для подмены в тестах через dependency injection.

Проверенные срезы:

```text
rg -n "Thread\.sleep|sleep\(|Task\.sleep|asyncAfter|Timer\(|DispatchQueue\.main\.asyncAfter|RunLoop\.current\.run" LayoutSwitcherTests LayoutSwitcher --glob '*.swift'
rg -n "ControlledEvaluationDelay|sleepProvider|delay|clock|timerFactory" LayoutSwitcher LayoutSwitcherTests --glob '*.swift'
rg -n "SelectionConverter\(|SmartPaste\(|Retyper\(|TypingPipeline\(|SequenceDetector\(" LayoutSwitcherTests --glob '*.swift'
rg -n "sleep:|sleepBeforeSequenceFlush|sleepBeforeFlush" LayoutSwitcherTests --glob '*.swift'
```

Что подтверждено:

- В тестах не найдено `Thread.sleep` и прямого реального ожидания через `Task.sleep`.
- `Retyper` принимает `sleep` closure и тесты подставляют no-op реализацию.
- `SmartPaste` принимает `sleep` closure и тесты подставляют no-op реализацию.
- `TypingPipeline` принимает `sleepBeforeSequenceFlush`, а sequence-тесты подставляют контролируемый `Task.yield()`.
- `SequenceDetector` получает `sleepBeforeFlush` через initializer, поэтому lookahead-задержка тестируема без реального ожидания.
- `SelectionConverter` имеет initializer с injected `sleep`, `pasteboardRead`, `pasteboardWrite`, `postKeyEvent` и `focusedElementProvider`.
- Тестовый helper `waitForAsyncWorkWindow` не вызывает реальный sleep; он использует controlled yield-loop через `waitUntil`, чтобы дать запланированным `Task` завершиться без wall-clock ожидания.

Найденные production-задержки:

- `TypingPipeline` / `SequenceDetector`: lookahead перед flush multi-word sequence.
- `Retyper`: ожидание подтверждения переключения раскладки.
- `SmartPaste`: короткая пауза после смены раскладки и synthetic paste.
- `SelectionConverter`: ожидание после synthetic copy/paste.
- `SecureInputObserver` и `AccessibilityPermission`: polling через injected timer factory / production timer.

Изменения в код не вносились.

Вывод: текущая реализация соответствует правилу deterministic tests. Реальные задержки изолированы в production defaults и доступны для подмены в тестах. Повторный запуск тестов не требовался, так как рабочий код и тестовая логика не менялись.

## Шаг 74. Аудит локализации пользовательских строк и accessibility label для per-app picker

Цель шага: проверить SwiftUI/AppKit слой на hardcoded user-facing strings и улучшить доступность элементов, которые визуально скрывают подписи, но должны иметь смысловое имя для VoiceOver.

Проверенные срезы:

```text
rg -n "Text\(\"|Button\(\"|Label\(\"|Toggle\(\"|Picker\(\"|Section\(\"|navigationTitle\(\"|help\(\"|alert\(\"|Menu\(\"" LayoutSwitcher --glob '*.swift'
rg -n "NSMenuItem\(|NSAlert|NSUserNotification|UNMutableNotificationContent|title = \"|subtitle = \"|informativeText = \"|messageText = \"" LayoutSwitcher --glob '*.swift'
```

Что найдено:

- Большинство UI-строк уже использует `String(localized:)` или является динамическим пользовательским/системным текстом.
- В `PerAppLayoutsTab` найден `Picker("", selection: ...)` с пустой подписью.
- Визуально подпись скрыта через `.labelsHidden()`, но пустая строка ухудшает accessibility-семантику для VoiceOver.

Что изменено:

- `Picker` в `PerAppLayoutsTab` получил локализованную смысловую подпись `settings.per-app-layouts.layout-picker`.
- В `Localizable.xcstrings` добавлены переводы для `en`, `ru`, `ro`, `uk`.
- Визуальный макет не изменен: `.labelsHidden()` сохранен.

Результат проверки:

```text
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'
Test run with 233 tests in 35 suites passed after 7.229 seconds.
** TEST SUCCEEDED **
```

Вывод: локализация и accessibility в per-app layout настройках стали лучше без изменения поведения UI. Каталог строк успешно компилируется, регрессий по тестам не обнаружено.

## Шаг 75. Аудит `@MainActor` границ и callback-closures

Цель шага: проверить Swift 6 isolation вокруг `Task`, системных callback-ов и injectable closures, где чаще всего появляются скрытые переходы между системными потоками и UI/main-actor состоянием.

Проверенные срезы:

```text
rg -n "Task \{|Task\.detached|DispatchQueue|NotificationCenter|Timer\(" LayoutSwitcher --glob '*.swift'
rg -n "var [A-Za-z0-9_]+: \(.*\) ->|let [A-Za-z0-9_]+: \(.*\) ->|@escaping \(.*\) ->|@escaping @MainActor|@Sendable" LayoutSwitcher --glob '*.swift'
rg -n "@MainActor|nonisolated|@preconcurrency|@unchecked Sendable" LayoutSwitcher --glob '*.swift'
```

Что подтверждено:

- `Task`-переходы из системных callback-ов явно возвращаются на `@MainActor`.
- `KeyboardEventTap` оставляет synchronous callback на main run loop и документирует, почему нельзя заменить его на async `Task` без потери возможности подавлять hotkey event.
- `InputSourceManager` и `FocusedAppObserver` переводят системные уведомления в main-actor обработчики.
- Timer-based polling в `AccessibilityPermission` и `SecureInputObserver` использует main-actor callback factory.
- DI-closures для `Retyper`, `SmartPaste`, `SelectionConverter`, `TypingPipeline`, `SequenceDetector` уже имеют main-actor границы там, где вызывают UI/system side effects.

Что улучшено:

- `NotificationManager.onUndoRequested` теперь имеет тип `(@MainActor () -> Void)?` вместо неаннотированного `(() -> Void)?`.
- Это делает контракт явным: undo из локального уведомления всегда является main-actor действием и может безопасно обращаться к `HotkeyCoordinator` / UI-bound состоянию.
- Поведение не изменилось; изменение только усиливает Swift 6 concurrency-семантику.

Результат проверки:

```text
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'
Test run with 233 tests in 35 suites passed after 7.325 seconds.
** TEST SUCCEEDED **
```

Вывод: критичные системные callback-и уже аккуратно возвращаются на main actor. Дополнительно укреплен контракт notification undo callback, чтобы будущие изменения не превратили UI-bound действие в неявно не изолированную closure.

## Шаг 76. Аудит `Sendable` и value semantics для моделей

Цель шага: проверить, что value types, которые могут участвовать в async-flow, системных callback-ах или UI-state snapshots, явно выражают безопасность передачи через concurrency boundaries. Отдельно важно не помечать `Sendable` live reference wrappers, которые должны оставаться изолированными через `@MainActor`.

Проверенные срезы:

```text
rg -n "struct .*:|enum .*:|final class|Sendable|@unchecked Sendable" LayoutSwitcher --glob '*.swift'
rg -n "Snapshot|Candidate|Result|Reason|Definition|Binding|Entry|Word|KeyEvent|LanguageID" LayoutSwitcher --glob '*.swift'
```

Что подтверждено:

- Ключевые domain snapshots уже имеют `Sendable`: `WordChar`, `CommittedWord`, `WordSeparator`, `KeyEvent`, `LanguageID`, `LanguagePair`, `RecentSwitchEntry`, `InputSourceSnapshot`, `LayoutPairSnapshot`, `PendingRetypeCandidate`, `RetypeResult`, `RetypeFailureReason`, `PipelineTunables`, `DetectionThresholds`.
- Live reference types остаются main-actor isolated classes: `WordBuffer`, `TypingPipeline`, `Retyper`, `InputSourceManager`, `FocusedAppObserver`, `NotificationManager`, UI controllers.
- `InputSource` и `RetypeInputSource` не помечались `Sendable`, потому что могут держать live system/TIS references. Для передачи в UI/read-only потоки уже используется `InputSourceSnapshot`.
- `LayoutPair` не помечался `Sendable`, потому что для безопасной передачи существует `LayoutPairSnapshot`.

Что улучшено:

- `EncodedKey` теперь явно `Sendable`.
- `HelpSection` теперь явно `Sendable`.
- `HelpSection.HelpLanguage` теперь явно `Sendable`.
- `HistoryTab.KindFilter` теперь явно `Sendable`.

Результат проверки:

```text
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'
Test run with 233 tests in 35 suites passed after 7.439 seconds.
** TEST SUCCEEDED **
```

Вывод: value semantics в проекте в целом уже выдержаны хорошо. Дополнительно укреплены несколько чистых value-only типов, а live wrappers оставлены под `@MainActor` isolation без небезопасного `@unchecked Sendable`.

## Шаг 77. Аудит DocC-документации для module API

Цель шага: проверить соблюдение DocC-стиля для API-поверхности модуля. В app target нет `public`, `open` или `package` Swift API, поэтому аудит сфокусирован на внутренних boundary types, которые используются между pipeline, retyper и тестами.

Проверенные срезы:

```text
awk '/^(struct|enum|protocol|final class|class|actor) / { if (prev !~ /^\/\/\//) print FILENAME ":" FNR ":" $0 } { prev=$0 }' LayoutSwitcher/**/*.swift
rg -n "^(public|open|package)\b" LayoutSwitcher --glob '*.swift'
rg -n "RetypeInputSource|RetypeFailureReason|RetypeResult" LayoutSwitcherTests LayoutSwitcher --glob '*.swift'
```

Что найдено:

- В проекте не обнаружено `public`, `open` или `package` declarations.
- Механический список declarations без `///` содержит шум из-за атрибутов между DocC-комментарием и объявлением, поэтому он не подходит для автоматической массовой правки.
- Самая полезная точка для улучшения документации на этом шаге: retype boundary models в `Retyper`.

Что изменено:

- `RetypeInputSource` получил DocC-описание назначения и различия между test fixtures и production instances.
- Поля `RetypeInputSource` получили краткие DocC-комментарии.
- `RetypeFailureReason` получил DocC-описание как Result-like domain failure enum вместо recoverable `throws`.
- Cases `RetypeFailureReason` получили пояснения причин отказа.
- `RetypeResult` и `succeeded` получили DocC-комментарии.

Результат проверки:

```text
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'
Test run with 233 tests in 35 suites passed after 7.313 seconds.
** TEST SUCCEEDED **
```

Вывод: публичной API-поверхности в app target нет, но важная внутренняя граница retype теперь документирована лучше. Это упрощает дальнейшие изменения и делает recoverable failure model более явной для тестов и будущих call sites.

## Шаг 78. Аудит cleanup после `UserDefaults` миграций

Цель шага: проверить, что после миграции persisted keys legacy-ключи не продолжают использоваться как основной storage path, а тесты явно разделяют current-key behavior и legacy migration behavior.

Проверенные срезы:

```text
rg -n "recentSwitches|exclusionBundleIDs|recentSwitches\.entries|exclusions\.bundleIDs" LayoutSwitcher LayoutSwitcherTests --glob '*.swift'
rg -n "UserDefaults\(|suiteName:|removeObject\(forKey:|set\(.*forKey:|object\(forKey:|array\(forKey:|data\(forKey:" LayoutSwitcher LayoutSwitcherTests --glob '*.swift'
```

Что подтверждено:

- В production-коде legacy keys `recentSwitches` и `exclusionBundleIDs` используются только как migration fallback.
- Current keys используются как основной storage path: `recentSwitches.entries` и `exclusions.bundleIDs`.
- `persist()` удаляет legacy key после успешной записи нового состояния.
- Legacy keys в тестах остались только там, где явно проверяется миграция старых пользовательских данных.

Что улучшено:

- Тест corrupted-data для `RecentSwitches` теперь кладет битые данные в текущий ключ `recentSwitches.entries`, а не в legacy key `recentSwitches`.
- Legacy path остается покрыт отдельным тестом `legacyDefaultsKeyIsMigratedToNamespacedKey`.
- Таким образом тесты теперь лучше разделяют два сценария: повреждение актуального storage и миграцию старого storage.

Результат проверки:

```text
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'
Test run with 233 tests in 35 suites passed after 7.239 seconds.
** TEST SUCCEEDED **
```

Вывод: migration cleanup выглядит корректно. Legacy keys сохранены только для обратной совместимости и тестирования миграции, а основной тест corrupted-data теперь защищает актуальный persisted key.

## Шаг 79. Аудит accessibility в SwiftUI-экранах

Цель шага: проверить SwiftUI UI на типовые accessibility-проблемы: пустые labels, image-only controls, декоративные `Image(systemName:)`, empty states и элементы, которые могут создавать шум для VoiceOver вместо полезного контекста.

Проверенные срезы:

```text
rg -n "Image\(systemName:|\.accessibility|labelsHidden\(|Picker\(\"\"|Button\(|Label\(" LayoutSwitcher/UI LayoutSwitcher/Hotkeys --glob '*.swift'
rg -n "empty|Empty|No |нет|description|Text\(String\(localized:" LayoutSwitcher/UI --glob '*.swift'
```

Что подтверждено:

- Кнопки в проверенных SwiftUI-экранах в основном имеют текстовые или `Label`-подписи.
- Пустой `Picker` из per-app layouts был исправлен ранее и теперь имеет локализованный label при сохраненном `.labelsHidden()`.
- Empty state для learned exceptions локализован и содержит текстовое описание.
- Exclusions, dictionaries, hotkeys и onboarding используют локализованные пользовательские строки.

Что улучшено:

- Декоративные крупные иконки в `OnboardingView` скрыты от accessibility tree через `.accessibilityHidden(true)`.
- Декоративные checkmark-иконки в списке layout-проверки onboarding скрыты от VoiceOver, потому что смысл уже передан текстом строки.
- Декоративная иконка приложения в `ExclusionsTab` скрыта от VoiceOver, чтобы озвучивались только имя приложения и bundle id.
- Визуальный интерфейс не изменен.
- Новые локализационные ключи не требовались.

Результат проверки:

```text
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'
Test run with 233 tests in 35 suites passed after 7.327 seconds.
** TEST SUCCEEDED **
```

Вывод: accessibility tree стал тише и полезнее для VoiceOver: декоративные символы больше не конкурируют с содержательным текстом, а проверенные controls сохраняют понятные labels.

## Шаг 80. Финальная консолидация аудита и остаточные риски

Цель шага: собрать текущее состояние аудита в один обзорный блок, чтобы отчет можно было использовать как проектную документацию: что уже улучшено, какие гарантии подтверждены тестами, и какие области остаются кандидатами для следующих итераций.

Итоговое состояние после серии шагов:

- Swift 6 strict concurrency: укреплены `@MainActor` границы, callback-closures, value-only `Sendable` типы и synchronous bridge для event tap.
- Dependency Injection: системные side effects вынесены в injectable closures для `NotificationManager`, `ExclusionList`, `UserDictionary`, `FocusedAppObserver`, `AccessibilityPermission`, `HistoryTab`, `SecureInputObserver`, `HelpContent`, `InputSourceManager`.
- Детерминированность тестов: реальные задержки изолированы в production defaults, тесты используют no-op или controlled yield-подходы.
- Error handling: recoverable domain errors представлены Result-like enums, а не `throws` для ожидаемых сценариев отказа.
- UserDefaults: persisted keys приведены к dot-namespaced стилю, legacy keys мигрируют мягко и удаляются после записи нового состояния.
- Logging: подтверждено использование `os.Logger`, `Self.logger` и privacy-аннотаций для пользовательских данных.
- Localization: help metadata и новые UI/accessibility labels перенесены в `.xcstrings` с переводами `en`, `ru`, `ro`, `uk`.
- Accessibility: декоративные SwiftUI icons скрыты от VoiceOver, а скрытые labels получили смысловые локализованные подписи.
- Documentation: важная внутренняя retype boundary теперь описана DocC-комментариями.
- Test coverage: набор вырос до 233 тестов в 35 suites, включая новые migration/accessibility-adjacent проверки и DI-focused tests.

Последнее подтвержденное состояние проверки:

```text
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'
Test run with 233 tests in 35 suites passed after 7.327 seconds.
** TEST SUCCEEDED **
```

Остаточные риски и наблюдения:

- Реальные macOS-интеграции все еще требуют ручного smoke-test на живой машине: Accessibility permission, CGEvent tap, Carbon hotkeys, local notifications, status menu и переключение системных input sources.
- Unit tests хорошо покрывают DI-слои, но не заменяют полноценный ручной UX-прогон onboarding/settings/status-item сценариев.
- `Swift6CodeQualityAudit.md` находится внутри `LayoutSwitcher/docs` и во время сборки копируется в app resources. Это допустимо для проектной документации внутри bundle, но если отчет не должен попадать в приложение, стоит отдельным шагом исключить `docs` из ресурсов target или перенести документацию за пределы app target.
- `xcodebuild` продолжает выводить предупреждение о выборе первого из двух matching macOS destinations. Это не ломает тесты, но для CI можно зафиксировать destination более явно.
- UI accessibility улучшался статически; отдельная проверка VoiceOver на реальном приложении пока не выполнялась.

Рекомендованный следующий практичный шаг:

- Проверить, должен ли каталог `LayoutSwitcher/docs` попадать в app bundle. Если нет, вынести отчет из target resources или настроить исключение, затем подтвердить `xcodebuild test`.

Вывод: проект после аудита находится в хорошем состоянии по Swift 6 safety, concurrency isolation, DI/testability, localization, logging и deterministic tests. Основные оставшиеся риски связаны не с чистотой Swift-кода, а с live macOS-интеграциями и упаковкой документации в bundle.

## Шаг 81. Исключение аудиторской документации из app bundle

Цель шага: проверить и исправить упаковку `LayoutSwitcher/docs/Swift6CodeQualityAudit.md` в `.app` bundle. Отчет нужен как проектная документация, но не является runtime resource приложения.

Что найдено:

- Target `LayoutSwitcher` использует `PBXFileSystemSynchronizedRootGroup` для всей папки `LayoutSwitcher`.
- Из-за этого markdown-файл отчета автоматически попадал в resources приложения.
- В предыдущих `xcodebuild` логах был виден `CpResource ... Swift6CodeQualityAudit.md`.

Что изменено:

- В `LayoutSwitcher.xcodeproj/project.pbxproj` добавлен `PBXFileSystemSynchronizedBuildFileExceptionSet` для app target.
- В `membershipExceptions` добавлен точный путь `docs/Swift6CodeQualityAudit.md`.
- Первичная попытка исключить всю папку `docs` оказалась недостаточной: Xcode продолжал копировать конкретный markdown-файл.
- После уточнения exception до файла Xcode удалил stale resource из app bundle.

Важное замечание по проверке:

- Первый прогон `xcodebuild test` внутри sandbox упал не из-за кода, а из-за запрета записи в `DerivedData` / `.xcresult` (`Operation not permitted`).
- Повторный прогон был выполнен с разрешением на запись Xcode DerivedData.

Результат проверки:

```text
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'
note: Removed stale file '.../LayoutSwitcher.app/Contents/Resources/Swift6CodeQualityAudit.md'
Test run with 233 tests in 35 suites passed after 7.530 seconds.
** TEST SUCCEEDED **
```

Вывод: аудиторский отчет остается в репозитории как проектная документация, но больше не упаковывается в runtime resources приложения. Полный тестовый набор после изменения `.xcodeproj` проходит успешно.

## Шаг 82. Live smoke-test запуска macOS-приложения

Цель шага: перейти от unit/build verification к минимальной live-проверке macOS app lifecycle: собрать приложение как `.app`, запустить свежесобранный bundle и убедиться, что процесс не падает сразу после старта.

Что проверено машинно:

```text
xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS' -derivedDataPath /private/tmp/layoutswitcher-smoke-derived
** BUILD SUCCEEDED **
```

Сборка выполнялась в отдельный `DerivedData` под `/private/tmp`, чтобы smoke-test не зависел от пользовательского Xcode cache и не упирался в sandbox-права на `~/Library/Developer/Xcode/DerivedData`.

После сборки был запущен свежий app bundle:

```text
open -n /private/tmp/layoutswitcher-smoke-derived/Build/Products/Debug/LayoutSwitcher.app
```

Проверка процесса:

```text
pgrep -fl LayoutSwitcher
75235 /private/tmp/layoutswitcher-smoke-derived/Build/Products/Debug/LayoutSwitcher.app/Contents/MacOS/LayoutSwitcher
```

Важное замечание по проверке:

- Первичная попытка прочитать список процессов внутри sandbox была заблокирована macOS (`pgrep: Cannot get process list`, `operation not permitted: ps`).
- Повторная проверка процесса была выполнена с разрешением на чтение process list.
- Старое предупреждение `xcodebuild` о выборе первого из двух matching macOS destinations сохраняется, но сборку не ломает.

Что этот шаг подтверждает:

- App target собирается как полноценный macOS `.app`.
- Bundle регистрируется LaunchServices во время build.
- Свежесобранный `LayoutSwitcher.app` запускается через LaunchServices.
- Процесс приложения остается жив после старта и не падает немедленно.

Что этот шаг не может доказать автоматически:

- Реальный `CGEventTap` перехватывает ввод в активном приложении.
- Accessibility/Input Monitoring разрешения выданы именно этому debug bundle.
- Carbon hotkeys реально срабатывают в пользовательской сессии.
- Переключение системных input sources работает в живом focused text field.
- Local notifications отображаются в Notification Center.

Вывод: базовый live lifecycle smoke-test пройден. Следующий практический шаг — ручной интерактивный smoke-test на живой машине: открыть UI, выдать/проверить Accessibility/Input Monitoring permission, набрать тестовые слова в текстовом поле, проверить hotkeys, status menu и реальные переключения раскладок.

## Шаг 83. Попытка автоматизированного интерактивного smoke-test ввода

Цель шага: попробовать перейти от проверки "приложение запустилось" к проверке живого ввода в macOS UI: поднять безопасное текстовое поле и сгенерировать тестовые keystrokes, которые потенциально должны проходить через системный event pipeline.

Предусловие:

```text
pgrep -fl '/private/tmp/layoutswitcher-smoke-derived/Build/Products/Debug/LayoutSwitcher.app/Contents/MacOS/LayoutSwitcher'
75235 /private/tmp/layoutswitcher-smoke-derived/Build/Products/Debug/LayoutSwitcher.app/Contents/MacOS/LayoutSwitcher
```

То есть свежесобранный `LayoutSwitcher.app` продолжал работать перед попыткой интерактивной проверки.

Попытка автоматизированного GUI-ввода:

```text
osascript
tell application "TextEdit" to activate
tell application "TextEdit" to make new document
tell application "System Events" to keystroke "ghbdtn"
```

Результат:

```text
execution error: System Events got an error: osascript is not allowed to send keystrokes. (1002)
```

Вывод по шагу:

- TextEdit-сценарий как безопасная цель для ввода выбран корректно.
- `LayoutSwitcher` оставался запущенным перед проверкой.
- macOS заблокировала генерацию синтетических keystrokes для управляющего процесса `osascript`.
- Это не указывает на падение или дефект `LayoutSwitcher`; это системное ограничение TCC/Accessibility для инструмента автоматизации.

Что остается проверить вручную или через отдельный подписанный UI-test/helper:

- Выдать нужные Accessibility/Input Monitoring разрешения самому `LayoutSwitcher` debug bundle.
- При необходимости выдать Accessibility-разрешение управляющему automation tool, если хотим продолжать именно автоматизированный live smoke-test.
- В TextEdit или другом текстовом поле набрать тестовые последовательности вроде `ghbdtn` и проверить фактическое auto-switch/retype поведение.
- Проверить registered hotkeys, status menu actions, pause/snooze и local notification undo.

Рекомендация: не считать этот шаг провалом приложения. Правильный следующий путь — либо ручной smoke-test с выданными macOS-разрешениями, либо создание отдельного тестового harness/helper с явно управляемыми permissions. Для текущего аудита достаточно зафиксировать, что автоматизация ввода уперлась в TCC, а не в runtime crash.

## Шаг 84. Повтор live input smoke-test после выдачи Accessibility-доступа

Цель шага: повторить автоматизированный GUI-ввод после того, как управляющему automation tool был выдан доступ, и отделить permission-блокировку от надежности самой методики тестирования.

Предусловие:

```text
pgrep -fl '/private/tmp/layoutswitcher-smoke-derived/Build/Products/Debug/LayoutSwitcher.app/Contents/MacOS/LayoutSwitcher'
75235 /private/tmp/layoutswitcher-smoke-derived/Build/Products/Debug/LayoutSwitcher.app/Contents/MacOS/LayoutSwitcher
```

Текущая выбранная input source в macOS:

```text
defaults read com.apple.HIToolbox AppleSelectedInputSources
KeyboardLayout Name = RussianWin
```

Повторный ввод через `System Events` после выдачи доступа:

```text
tell application "TextEdit" to activate
tell application "TextEdit" to make new document
tell application "System Events" to keystroke "ghbdtn "
```

Результат из TextEdit:

```text
Фффdфф 
```

Что подтверждено:

- Permission-блокировка из шага 83 снята: `System Events` больше не возвращает ошибку `osascript is not allowed to send keystrokes`.
- `LayoutSwitcher` продолжал работать во время проверки.
- TextEdit принимал синтетический ввод.

Что важно:

- Результат `Фффdфф ` не является валидным доказательством дефекта `LayoutSwitcher`.
- Автоматизированный `System Events keystroke "ghbdtn "` при активной `RussianWin` не соответствует ручному сценарию "пользователь физически нажимает клавиши g-h-b-d-t-n на English layout".
- Попытка перейти на низкоуровневые `key code` для физической калибровки оказалась ненадежной в TextEdit automation path: ввод не дал стабильного считываемого результата через clipboard.

Вывод: после выдачи доступа автоматизация ввода стала возможной, но методика через `System Events` остается недостаточно достоверной для проверки auto-switch/retype поведения. Для честной live-проверки нужен ручной smoke-test с физическим вводом или отдельный signed helper/UI-test harness, который явно управляет input source, фокусом и permissions.

Мини-чеклист ручного smoke-test:

- Запустить свежесобранный `LayoutSwitcher.app`.
- Убедиться, что debug bundle имеет Accessibility/Input Monitoring permission.
- Переключиться на English layout.
- Открыть TextEdit и физически набрать `ghbdtn `.
- Ожидаемый пользовательский результат для EN->RU сценария: `привет `.
- Проверить status menu, pause/snooze, registered hotkeys и notification undo.

## Шаг 85. Ручное подтверждение live smoke-test

Цель шага: закрыть оставшуюся после автоматизированной проверки зону риска — реальное поведение приложения при физическом пользовательском вводе в macOS session.

Проверка выполнена вручную пользователем после выдачи нужного доступа:

- Приложение запущено.
- Accessibility/Input Monitoring permission выдан.
- Физический ввод в живом текстовом поле работает.
- Auto-switch/retype поведение подтверждено пользователем как рабочее.

Результат:

```text
Manual live smoke-test passed.
```

Вывод: оставшийся ключевой риск, который не мог быть честно доказан через `System Events`, закрыт ручной проверкой. В сочетании с предыдущими `xcodebuild test`, `xcodebuild build` и live app lifecycle smoke-test это дает полный практический контур подтверждения: код собирается, тесты проходят, приложение запускается, и базовое пользовательское поведение работает в реальной macOS-сессии.

## Финальный статус аудита Swift 6 code quality

Аудит качества кода на текущем этапе можно считать завершенным по основному контуру. Проект прошел последовательную проверку и доработку по ключевым зонам Swift 6, macOS integration и maintainability.

Подтверждено:

- Swift 6 strict concurrency используется как базовый режим сборки.
- UI-bound и shared mutable state изолированы через `@MainActor`.
- Ключевые value snapshots и boundary models имеют явные `Sendable`/value semantics там, где это полезно и безопасно.
- Прямые side effects в основных сервисах вынесены в dependency injection seams.
- Recoverable domain failures представлены Result-like enums, а не аварийными runtime-путями.
- Force unwrap / forced cast / `try!` в рабочем коде и тестах не обнаружены.
- Логирование построено на `os.Logger`, с privacy-аннотациями для пользовательских данных.
- UserDefaults keys приведены к dot-namespaced стилю с мягкой миграцией legacy keys.
- Локализация UI/help/accessibility строк покрывает `en`, `ru`, `ro`, `uk`.
- SwiftUI accessibility tree очищен от декоративного шума в проверенных местах.
- Важные внутренние boundary types дополнены DocC-документацией.
- Аудиторская документация исключена из runtime resources `.app`.

Последние подтвержденные проверки:

```text
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'
Test run with 233 tests in 35 suites passed
** TEST SUCCEEDED **
```

```text
xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS' -derivedDataPath /private/tmp/layoutswitcher-smoke-derived
** BUILD SUCCEEDED **
```

```text
Manual live smoke-test passed.
```

Итоговый вывод:

Проект находится в хорошем состоянии для текущего этапа: статическая архитектурная чистота, Swift 6 safety, тестируемость, сборка, полный тестовый набор, запуск `.app` и базовое живое пользовательское поведение подтверждены.

Оставшиеся пункты не являются блокерами:

- Зафиксировать более точный `xcodebuild -destination`, чтобы убрать предупреждение о выборе первой matching macOS destination.
- При желании включить warnings-as-errors gate как отдельное проектное решение.
- При желании создать отдельный signed helper/UI-test harness для автоматизированной проверки реального macOS input pipeline.
- Периодически повторять ручной smoke-test после крупных изменений в event tap, hotkeys, input source switching или onboarding/settings UI.

Рекомендованный режим дальнейшей работы:

- Для обычных изменений: targeted tests → full `xcodebuild test`.
- Для изменений в macOS integration: targeted tests → full `xcodebuild test` → manual live smoke-test.
- Для UI/accessibility изменений: targeted tests → manual UI/VoiceOver smoke-test.

Финальный статус: основной аудит Swift 6 code quality закрыт успешно.

## Шаг 86. First-run recommended exclusions для macOS

Цель шага: улучшить первый пользовательский опыт и снизить риск нежелательных автокоррекций в системных, developer и security-sensitive приложениях. Идея: при первом запуске заполнить exclusions рекомендованным списком, но не превращать его в жесткий blacklist.

Что было до правки:

- `ExclusionList` уже имел baseline defaults и использовал их при отсутствии сохраненного списка.
- Контракт first-run seed был неявным.
- Не было отдельного persisted-флага, который явно фиксирует факт применения стартового seed.

Что изменено:

- Добавлен persisted-флаг `exclusions.defaultSeedApplied`.
- First-run seed стал явным: если текущего или legacy списка нет и seed еще не применялся, список заполняется `ExclusionList.defaults`.
- Если seed уже применялся, но сохраненного списка нет, дефолты не возвращаются автоматически.
- Если пользователь удалил приложение из exclusions, повторная инициализация не добавляет его обратно.
- Recommended defaults расширены системными macOS apps:

```text
com.apple.Terminal
com.apple.Console
com.apple.ActivityMonitor
com.apple.ScriptEditor2
com.apple.Automator
com.apple.shortcuts
```

Также сохранены уже существующие developer/security-sensitive defaults, включая `iTerm`, `VSCode`, JetBrains IDEs, `1Password` и сам `GIH.LayoutSwitcher`.

Добавленные тесты:

- `firstRunSeedsRecommendedDefaults`
- `userRemovedDefaultIsNotSeededAgain`
- `seedAppliedWithoutStoredListDoesNotReapplyDefaults`

Targeted-проверка:

```text
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/ExclusionListTests
Test run with 5 tests in 1 suite passed
** TEST SUCCEEDED **
```

Full suite:

```text
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'
Test run with 236 tests in 35 suites passed after 7.415 seconds.
** TEST SUCCEEDED **
```

Вывод: recommended exclusions теперь работают как одноразовый first-run UX seed, уважают пользовательские удаления и покрыты deterministic tests. Это снижает вероятность неприятного первого опыта в Terminal/Console/Script Editor/Automation tools, не мешая пользователю вручную управлять списком исключений.

## Шаг 87. Cleanup пустых `.lproj` каталогов

Цель шага: убрать из source tree пустые legacy-каталоги локализаций, которые больше не несут содержимого после перехода на string catalogs.

Что было проверено перед удалением:

- В source tree существовали пустые каталоги `LayoutSwitcher/en.lproj`, `LayoutSwitcher/ro.lproj`, `LayoutSwitcher/ru.lproj`, `LayoutSwitcher/uk.lproj`.
- Реальные исходники локализации находятся в `LayoutSwitcher/Localizable.xcstrings` и `LayoutSwitcher/InfoPlist.xcstrings`.
- Во время сборки Xcode сам генерирует соответствующие `.lproj` resources в build products из `.xcstrings`.

Что изменено:

```text
rmdir LayoutSwitcher/en.lproj LayoutSwitcher/ro.lproj LayoutSwitcher/ru.lproj LayoutSwitcher/uk.lproj
```

Для удаления использовался `rmdir`, а не recursive remove: если бы внутри каталогов были файлы, команда завершилась бы ошибкой и не удалила бы содержимое.

Вывод: пустые legacy localization folders удалены из рабочего source tree. Локализация остается в string catalogs, поэтому runtime localization model не меняется.

## Шаг 88. Отдельная menu bar icon вместо app-style/status text

Цель шага: улучшить визуальное качество и читаемость иконки в верхней панели macOS. App icon не подходит для menu bar: там нужна compact template icon, которую macOS может корректно перекрашивать под светлую/темную панель.

Что было до правки:

- Status item использовал SF Symbol `keyboard` / `keyboard.fill` как основу для языкового badge.
- При первичной настройке кнопки рядом с иконкой выставлялся текст `LS`.
- Визуально это выглядело не как отдельный glyph приложения для menu bar, а как generic keyboard icon с дополнительным текстом.

Что изменено:

- `StatusBarIconRenderer` теперь рисует отдельный template glyph на основе `arrow.triangle.2.circlepath`.
- Для языковых состояний внутри glyph отображается текущий 2-letter badge: `EN`, `RU`, `UK`, `RO`.
- Старый текст `LS` рядом с иконкой в `StatusItemController.configureButton()` убран.
- App icon не используется для status bar: Dock/Finder и menu bar остаются разными визуальными контекстами.
- Secure/disabled states продолжают использовать отдельные системные template symbols.

Добавленные тесты:

- `statusBarLanguageIconIsTemplateImage`
- `statusBarFallbackIconIsTemplateImage`

Важное замечание по проверке:

- Первый targeted-прогон выявил недостающий `import AppKit` в новом тестовом файле для доступа к `NSImage.isTemplate` и `NSImage.size`.
- После добавления импорта targeted-проверка прошла успешно.

Targeted-проверка:

```text
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/StatusItemControllerTests
Test run with 5 tests in 1 suite passed after 0.022 seconds.
** TEST SUCCEEDED **
```

Full suite:

```text
xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'
Test run with 238 tests in 35 suites passed after 7.220 seconds.
** TEST SUCCEEDED **
```

Вывод: верхняя панель теперь использует отдельную нативную monochrome/template иконку переключения, а не app-style icon или текстовый `LS` рядом с кнопкой. Это ближе к macOS menu bar conventions и сохраняет полезный языковой статус прямо внутри glyph.

## Шаг 89. Обновление app icon из `ls_logo.png`

Цель шага: заменить именно иконку приложения для Dock/Finder/About, не смешивая ее с отдельной monochrome/template иконкой верхней панели.

Исходное изображение:

```text
/Users/epythonic/Projects/XCode/LayoutSwitcher/ls_logo.png
pixelWidth: 1254
pixelHeight: 1254
format: png
```

Что изменено:

- Все PNG внутри `LayoutSwitcher/Assets.xcassets/AppIcon.appiconset` перегенерированы из `ls_logo.png`.
- `Contents.json` не менялся: сохранены существующие macOS icon slots и имена файлов.
- Status bar icon из шага 88 не менялась и остается отдельным template glyph.

Перегенерированные размеры:

```text
16x16
32x32
64x64
128x128
256x256
512x512
1024x1024
```

Вывод: app icon теперь берется из предоставленного `ls_logo.png`, а menu bar icon остается отдельной нативной монохромной иконкой для верхней панели macOS.
