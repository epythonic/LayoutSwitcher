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

## Шаг 90. Повторный глубокий аудит качества кода Swift 6

Дата повторного прохода: 2026-05-15.

Цель: повторно проверить качество кода после основного Swift 6 аудита, полировки первого запуска, локализаций, status/app icon и подготовки tester DMG.

Ограничение прохода: это статический аудит и документационный отчет. Сборка и тесты в этом проходе не запускались, потому что изменений в Swift-код не вносилось.

Затронутые файлы: только этот отчет `LayoutSwitcher/docs/Swift6CodeQualityAudit.md`.

### Краткий вердикт

Проект находится в хорошем состоянии для приватного использования и дальнейшего тестирования. Основной контур Swift 6 safety выглядит зрелым: shared mutable state в ключевых местах изолирован через `@MainActor`, side effects в большинстве сервисов вынесены в dependency injection seams, forced unwrap / forced cast / `try!` статическим поиском не обнаружены, тестовая база использует Swift Testing.

Критических блокеров уровня P0 не найдено.

Есть несколько важных качественных долгов, которые лучше закрыть до следующего публичного/долгого релиза:

- P1: дрейф идентификатора приложения: target bundle identifier равен `GM.LayoutSwitcher`, но first-run exclusions и часть runtime-констант все еще используют `GIH.LayoutSwitcher`.
- P2: `LaunchAtLoginManager` и `SettingsView.exportLogs()` остаются менее тестируемыми, чем остальные сервисы, потому что напрямую обращаются к системным side effects.
- P2: проектная политика "zero warnings" пока не закреплена настройкой warnings-as-errors в Xcode project.
- P2: `KeyboardEventTap` содержит осознанный `MainActor.assumeIsolated` путь без отдельного тестового покрытия wrapper-логики.
- P3: в тестовом target остался шаблонный пустой `LayoutSwitcherTests.example()`.
- P3: string catalog содержит несколько нейтральных/динамических строк без переводов, которые стоит либо локализовать, либо явно исключить из пользовательского смысла.
- P3: `PresentationModeDetector` дублирует default set в init и static property, что создает риск рассинхронизации.

### Что было проверено

- Project settings: `SWIFT_VERSION = 6.0`, entitlements, hardened runtime, bundle identifiers, synchronized docs exception.
- Swift safety scan: forced unwrap-like patterns, `try!`, `as!`, `fatalError`, `preconditionFailure`, `print`, `NSLog`, `@unchecked Sendable`.
- Concurrency scan: `@MainActor`, `@Observable`, `Sendable`, `Task { @MainActor ... }`, `MainActor.assumeIsolated`.
- Dependency injection scan: прямые обращения к `UserDefaults.standard`, `FileManager.default`, `Bundle.main`, `NSWorkspace.shared`, `UNUserNotificationCenter.current()`, `Task.sleep`, `Timer`.
- Testing scan: Swift Testing markers, XCTest markers, `Thread.sleep`.
- Localization scan: полнота `Localizable.xcstrings` по `en`, `ru`, `ro`, `uk`; consistency H2 sections в `Help_en.md`, `Help_ru.md`, `Help_ro.md`, `Help_uk.md`.
- Runtime identity scan: `GIH.LayoutSwitcher` vs `GM.LayoutSwitcher`.
- Distribution docs scan: README содержит release link, Gatekeeper, Accessibility и Input Monitoring guidance.

### Положительные наблюдения

- `project.pbxproj` показывает `SWIFT_VERSION = 6.0` для app/test targets.
- App target использует `LayoutSwitcher/LayoutSwitcher.entitlements`.
- Hardened Runtime включен для app target.
- Entitlements явно отключают App Sandbox и включают `com.apple.security.device.input-monitoring`, что соответствует CGEventTap/Input Monitoring модели.
- `LayoutSwitcher/docs/Swift6CodeQualityAudit.md` уже добавлен в `membershipExceptions`, поэтому этот отчет не должен попадать в runtime resources приложения.
- Поиск не нашел `try!`, `as!`, `fatalError`, `preconditionFailure`, `assertionFailure`, `print`, `debugPrint`, `dump`, `NSLog` в рабочем Swift-коде.
- Отдельный поиск forced unwrap-like паттернов не дал находок.
- Поиск `import XCTest`, `XCTAssert`, `Thread.sleep` в `LayoutSwitcherTests` не дал находок.
- Основные stateful сервисы помечены `@MainActor`, а value snapshots имеют `Sendable` там, где это важно: `WordChar`, `CommittedWord`, `KeyEvent`, `InputSourceSnapshot`, `RecentSwitchEntry`, `PendingRetypeCandidate`, `RetypeResult`, `LanguageID`, hotkey models.
- Системные границы в большинстве критичных мест инъектируются через closures: `NotificationManager`, `FocusedAppObserver`, `AccessibilityPermission`, `SecureInputObserver`, `InputSourceManager`, `Retyper`, `TypingPipeline`, `UserDictionary`, `OnboardingCompletionStore`.
- Help markdown files имеют одинаковый набор секций для `en`, `ru`, `ro`, `uk`.

### P1. Bundle identity drift: `GM.LayoutSwitcher` vs `GIH.LayoutSwitcher`

Факт:

- Xcode target bundle identifier: `GM.LayoutSwitcher`.
- `ExclusionList.defaults` содержит `"GIH.LayoutSwitcher"`.
- `ExclusionListTests.firstRunSeedsRecommendedDefaults()` тоже ожидает `"GIH.LayoutSwitcher"`.
- `LaunchAtLoginManager` содержит private static `serviceName = "GIH.LayoutSwitcher"`.
- `os.Logger` subsystem и export logs predicate также используют `GIH.LayoutSwitcher`.

Почему это важно:

- Для логирования `GIH.LayoutSwitcher` может быть осознанным стабильным subsystem namespace, хотя его стоит явно зафиксировать как выбранное имя.
- Для exclusions это выглядит как реальный stale identifier. Если приложение должно исключать само себя из auto-switch, first-run seed сейчас не совпадает с фактическим `PRODUCT_BUNDLE_IDENTIFIER`.
- Тест закрепляет stale value, поэтому не поймает ошибку после изменения bundle identifier.
- `LaunchAtLoginManager.serviceName` сейчас не используется, но его наличие создает ложную уверенность и усиливает рассинхронизацию identity модели.

Рекомендация:

- Ввести единый источник runtime identity, например `AppIdentity.bundleIdentifierFallback`.
- Для self-exclusion использовать фактический `Bundle.main.bundleIdentifier ?? "GM.LayoutSwitcher"` либо явно добавить `GM.LayoutSwitcher` в default exclusions.
- Для мягкой миграции можно временно оставить `GIH.LayoutSwitcher` рядом с `GM.LayoutSwitcher`, чтобы не ломать старые пользовательские настройки.
- Обновить `ExclusionListTests` так, чтобы тест проверял актуальный self bundle ID, а не историческую строку.
- Удалить unused `serviceName` из `LaunchAtLoginManager` или заменить его на реально используемый идентификатор, если появится helper/service registration path.

Приоритет: высокий, потому что это маленькая правка с понятным пользовательским эффектом.

### P2. Launch-at-login менеджер хуже изолирован, чем остальные сервисы

Факт:

- `LaunchAtLoginManager` напрямую использует `SMAppService.mainApp`.
- В тестах не найден `LaunchAtLoginManagerTests`.
- В отличие от `NotificationManager`, `InputSourceManager`, `AccessibilityPermission`, `Retyper` и других сервисов, здесь нет injected closures для `status`, `register`, `unregister`.

Почему это важно:

- Текущая реализация проста, но ее сложно покрыть deterministic tests без реального system state.
- Логика sync `appState.launchAtLogin` в `AppDelegate` зависит от системного статуса, но unit-level contract для success/failure paths не закреплен.
- Это выбивается из собственного проектного правила: "Every service class must expose a designated initializer with injected closures for all side effects".

Рекомендация:

- Добавить initializer с closures или маленький protocol facade:
  - `statusProvider: () -> SMAppService.Status`
  - `register: () throws -> Void`
  - `unregister: () throws -> Void`
- Покрыть тестами:
  - enabled status отражается корректно;
  - register success возвращает true;
  - register failure возвращает false и не меняет UI state напрямую;
  - unregister failure возвращает false;
  - `.notFound` дает false и логируемую ошибку.

Приоритет: средний. Это не ломает текущий запуск, но снижает уверенность в regression safety.

### P2. Export logs logic живет прямо во View и блокирует main-thread path

Факт:

- `SettingsView.exportLogs()` создает `NSSavePanel`, `Process`, `Pipe`, запускает `/usr/bin/log show` и читает `readDataToEndOfFile()` прямо внутри view-level метода.
- Эта логика не вынесена в отдельный сервис и не имеет injected process runner / file writer.

Почему это важно:

- `log show --last 1h` может быть относительно тяжелой операцией.
- Синхронное чтение output pipe может подвиснуть UI на слабой машине или при большом объеме логов.
- Ошибки экспорта сейчас трудно тестировать без реального `Process`.
- View получает слишком много ответственности: UI, выбор файла, запуск процесса, запись файла, логирование ошибки.

Рекомендация:

- Вынести в `LogExporter` или `DiagnosticsLogExporter`.
- Инъектировать process runner и writer.
- Запускать экспорт вне main actor, а UI обновлять после завершения.
- Добавить тесты на аргументы `log show`, успешную запись и failure path.

Приоритет: средний. Это quality/testability issue, не основной runtime blocker.

### P2. Политика zero warnings не закреплена project gate

Факт:

- В `project.pbxproj` найдены `SWIFT_VERSION = 6.0`, `ENABLE_HARDENED_RUNTIME = YES`, `CODE_SIGN_ENTITLEMENTS`.
- `SWIFT_TREAT_WARNINGS_AS_ERRORS` и `GCC_TREAT_WARNINGS_AS_ERRORS` поиском не найдены.

Почему это важно:

- В правилах проекта явно указано: zero errors, zero warnings on `xcodebuild build`.
- Сейчас это остается дисциплиной ручной проверки, а не настройкой проекта.
- Любое новое warning может попасть в локальную сборку или CI незамеченным, если никто специально не смотрит полный лог.

Рекомендация:

- Добавить warnings-as-errors gate для Debug/Release после отдельного build pass.
- Если включение сразу шумное, сначала зафиксировать текущие warnings в отчете и закрыть их отдельным шагом.
- Для CI/локальной проверки использовать команду:

```text
xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'
```

Приоритет: средний. Включать только после явной проверки build output, чтобы не заблокировать разработку неожиданными SDK warnings.

### P2. `MainActor.assumeIsolated` в event tap остается самым чувствительным concurrency boundary

Факт:

- `KeyboardEventTap.tapCallback` проверяет `Thread.isMainThread`.
- После проверки вызывается `handleSynchronousMainRunLoopCallback(...)`.
- Внутри используется `MainActor.assumeIsolated`.
- Комментарий объясняет причину: callback должен остаться синхронным, потому что `nil` suppresses hotkey event before system sees it.
- Тестов по `KeyboardEventTap` поиском не найдено.

Почему это важно:

- Это осознанное и, вероятно, правильное место для `assumeIsolated`, потому что event tap установлен на main run loop и hotkey suppression должен быть синхронным.
- Но это все равно самый хрупкий boundary Swift 6 strict concurrency: если установка tap/run loop когда-нибудь изменится, safety будет зависеть от runtime guard.
- Отсутствие тестов на pass-through/off-main branch и hotkey suppression branch оставляет эту область в основном на manual smoke-test.

Рекомендация:

- Не переписывать на `Task { @MainActor ... }` без отдельного дизайна, потому что это сломает synchronous suppression.
- Добавить minimal seam/test harness вокруг decision logic:
  - synthetic event passes through;
  - hotkey handler true returns nil;
  - regular key event calls `onKeyEvent`;
  - off-main callback branch passes event through.
- Сохранить комментарий как архитектурное решение.

Приоритет: средний. Код выглядит осознанно, но это зона, которую стоит защитить тестами.

### P3. В тестовом target остался template placeholder test

Факт:

- `LayoutSwitcherTests/LayoutSwitcherTests.swift` содержит `@Test func example() async throws` без assertions.
- Файл содержит шаблонный комментарий `Write your test here...`.

Почему это важно:

- Тест не проверяет поведение.
- Он увеличивает число тестов, но не добавляет уверенности.
- В зрелом проекте такой файл выглядит как случайный остаток Xcode template.

Рекомендация:

- Удалить файл, если он не нужен.
- Или заменить на маленький smoke-level invariant, например:
  - `LanguageID.allCases` содержит `en`, `ru`, `uk`, `ro`;
  - `ExclusionList.defaults` содержит актуальный app bundle ID;
  - `HotkeyAction` default bindings include expected core actions.

Приоритет: низкий, но это быстрая уборка.

### P3. String catalog содержит несколько нейтральных/динамических missing-localization entries

Факт:

- Проверка `Localizable.xcstrings` на отсутствие одной из локалей `en`, `ru`, `ro`, `uk` вернула:
  - `%@ (%@)`
  - `%@ -> %@`
  - `%@ <-> %@`
  - `•`

Примечание:

- В исходном Swift-коде эти строки соответствуют динамическому отображению layout names, pairs, recent corrections и декоративному separator dot.
- Это не выглядит как реальная пользовательская фраза без перевода.

Почему это важно:

- Такие entries создают шум в localization workflow.
- При будущей работе переводчик может принять их за незавершенные строки.

Рекомендация:

- Если это именно neutral formatting symbols, оставить как nonlocalized через явный подход в SwiftUI, где это уместно.
- Если это пользовательские шаблоны, добавить локализации с полноценными keys.

Приоритет: низкий.

### P3. `PresentationModeDetector` имеет два источника default bundle IDs

Факт:

- `PresentationModeDetector.init(...)` содержит inline default set.
- Ниже есть `static let defaultPresentationBundleIDs` с похожим набором.
- Тест проверяет `PresentationModeDetector.defaultPresentationBundleIDs.contains("com.apple.iWork.Keynote")`, но default initializer использует не эту static property.

Почему это важно:

- При добавлении нового presentation app можно обновить static set и забыть inline default set.
- Тест при этом может пройти, хотя runtime default behavior не изменится.

Рекомендация:

- Заменить default parameter на `presentationBundleIDs: Set<String> = Self.defaultPresentationBundleIDs`.
- Добавить тест, что default detector использует static defaults.

Приоритет: низкий.

### Дополнительные наблюдения без статуса дефекта

- `UserDictionary` использует throwing closures для IO, но переводит recoverable failures в лог и пустой результат. Это не конфликтует с правилом "do not use throws for recoverable domain errors", потому что throws здесь отражает Foundation IO boundary, а не domain-level decision.
- `NotificationManager` напрямую использует `UNUserNotificationCenter.current()` только внутри default injected closures, что соответствует DI-паттерну проекта.
- `Retyper` делает preflight до destructive phase, возвращает `RetypeResult` с explicit failure reasons и не стирает текст до проверки layout/encoding. Это сильная архитектурная часть.
- `FocusedAppObserver` и `InputSourceManager` используют `Task { @MainActor ... }` для async delivery из системных callbacks, что выглядит правильно для несинхронных notification paths.
- `CarbonHotkeyManager` возвращает из callback сразу и доставляет action через `Task { @MainActor ... }`; это приемлемо, потому что suppression keyDown отдельно обрабатывается `KeyboardEventTap`.
- Non-ASCII в Swift source в основном оправдан domain-моделью: словари, keyboard mappings, Romanian diacritics, Russian/Ukrainian glyphs, UI separators. Однако в logs/comments встречаются Unicode arrows и em dash; это style-level вопрос, не дефект.

### Рекомендуемый следующий batch улучшений

1. Исправить bundle identity drift: добавить `GM.LayoutSwitcher` в self-exclusion, обновить тест, убрать/прояснить stale `GIH.LayoutSwitcher` там, где это не logger subsystem.
2. Удалить или заменить placeholder `LayoutSwitcherTests.example()`.
3. Убрать duplication в `PresentationModeDetector.defaultPresentationBundleIDs`.
4. Вынести `LaunchAtLoginManager` на injected side-effect closures и добавить unit tests.
5. Вынести export logs из `SettingsView` в тестируемый diagnostics service.
6. После этих правок запустить targeted tests, затем полный `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'`.
7. Отдельным решением включить warnings-as-errors после чистой build-проверки.

Итог повторного аудита: проект остается пригодным для приватного использования и тестирования. Основной code quality высокий, но следующий разумный шаг уже не широкий рефакторинг, а точечная уборка identity/testability gaps вокруг bundle ID, login item, diagnostics export и event tap coverage.

### Шаг 91. Усиление тестового покрытия `KeyboardEventTap`

**Дата:** 2026-05-15

**Цель шага:** закрыть риск из повторного аудита вокруг синхронной границы `CGEventTap` -> `MainActor.assumeIsolated`, где ошибка поведения может привести к пропуску hotkey-событий или повторной обработке synthetic events.

**Что изменено:**

- `KeyboardEventTap.handle(type:event:)` открыт на уровне модуля для `@testable import` без изменения runtime-поведения приложения.
- Добавлен набор `KeyboardEventTapTests` на Swift Testing.
- Покрыты сценарии:
  - hotkey consume возвращает `nil` и не передаёт событие в pipeline;
  - обычный keyDown сначала проходит через hotkey handler, затем через `onKeyEvent`;
  - auto-repeat события игнорируются обработчиками и пропускаются дальше;
  - synthetic events не попадают в обработчики, чтобы не создавать feedback loop;
  - disabled tap event безопасно пропускается дальше.

**Результат проверки:**

- Targeted: `KeyboardEventTapTests` — 5 тестов, `** TEST SUCCEEDED **`.
- Full regression: 254 теста в 38 наборах, `** TEST SUCCEEDED **`.

**Вывод:** риск вокруг event tap boundary стал ниже: критическая синхронная ветка теперь закреплена автоматическими тестами, а архитектура `CGEventTap` сохранена без асинхронного разрыва hotkey-решения.

### Шаг 92. Включение `warnings-as-errors` для Swift-сборки

**Дата:** 2026-05-15

**Цель шага:** превратить требование "zero warnings" из договорённости в автоматический build gate, чтобы новые Swift-предупреждения не проходили незамеченными.

**Что изменено:**

- В `LayoutSwitcher.xcodeproj/project.pbxproj` для project-level Debug/Release добавлен `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`.
- Настройка наследуется app, unit test и UI test targets.
- При проверке `xcodebuild` подтвердил передачу `-warnings-as-errors` в Swift compiler invocation.

**Что нашёл новый gate:**

- `AccessibilityPermissionTests` использовал mutable local state (`trusted`) после захвата closure.
- `SecureInputObserverTests` использовал mutable local state (`secureInputEnabled`) после захвата closure.

**Что исправлено:**

- В обоих тестовых наборах mutable state перенесён в `@MainActor` fixture-классы.
- Closure-инъекции остались детерминированными и не зависят от реального состояния macOS.

**Результат проверки:**

- `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- Targeted: `SecureInputObserverTests` — 3 теста, `** TEST SUCCEEDED **`.
- Full regression: 254 теста в 38 наборах, `** TEST SUCCEEDED **`.

**Вывод:** проект теперь защищён от новых Swift warning-regressions на уровне Xcode-сборки. Найденные warning-as-error проблемы были в тестовых stubs и исправлены без изменения runtime-логики приложения.

### Шаг 93. Очистка технических строк в `Localizable.xcstrings`

**Дата:** 2026-05-15

**Цель шага:** убрать нейтральные/технические записи из string catalog и явно закрыть форматные строки, которые Xcode держал в состоянии `new` или без локализаций.

**Что найдено:**

- В `Localizable.xcstrings` были технические ключи без локализаций: пустая строка и `•`.
- Форматные шаблоны `%@ (%@)`, `%@ → %@`, `%@ ↔ %@` имели неполные локализации и состояние `new`.
- `•` использовался как визуальный разделитель в `LearningTab`, а не как пользовательская строка.

**Что изменено:**

- `LearningTab` теперь использует `Text(verbatim: "•")`, чтобы визуальный bullet не попадал в локализацию.
- Из `Localizable.xcstrings` удалены технические ключи пустой строки и `•`.
- Для форматных шаблонов добавлены явные `en`, `ru`, `ro`, `uk` значения с positional placeholders:
  - `%1$@ (%2$@)`
  - `%1$@ → %2$@`
  - `%1$@ ↔ %2$@`

**Результат проверки:**

- `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- Full regression: 254 теста в 38 наборах, `** TEST SUCCEEDED **`.

**Вывод:** каталог локализаций стал чище: технический UI-разделитель больше не локализуется, а форматные строки теперь явно покрыты всеми поддерживаемыми языками и проходят сборку с `warnings-as-errors`.

### Шаг 94. Первый слой DocC-документации для runtime core

**Дата:** 2026-05-15

**Цель шага:** начать закрывать пробелы в Swift DocC-документации для важных внутренних API без большого косметического рефакторинга.

**Что найдено:**

- Автоматический обзор показал десятки internal типов без `///`-комментариев.
- Для одного шага выбран приоритетный runtime core: состояние приложения, разрешения, secure input, typing pipeline и retype-движок.

**Что изменено:**

- В `AppState` добавлены DocC-комментарии к `SnoozeDuration`, `AppState`, ключевым observable-свойствам, init и snooze-методам.
- В `AccessibilityPermission` и `SecureInputObserver` задокументированы polling-протоколы и их invalidation contract.
- В `TypingPipeline` добавлено описание роли pipeline как границы между keyboard input и сервисами приложения.
- В `Retyper` добавлено описание безопасной модели retyping: layout selection, confirmation, injected side effects.

**Результат проверки:**

- `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- Full regression: 254 теста в 38 наборах, `** TEST SUCCEEDED **`.

**Вывод:** документация ключевого runtime слоя стала понятнее для будущей поддержки, при этом runtime-поведение приложения не изменялось.

### Шаг 95. Второй слой DocC-документации для detector/pipeline support

**Дата:** 2026-05-15

**Цель шага:** продолжить закрывать пробелы в Swift DocC-документации для слоя, который объясняет решения detector и управление retype-потоком.

**Что изменено:**
- В `LanguageScoring` задокументирован scoring contract и fallback natural-language probability.
- В `LayoutDetector` задокументированы доменные решения `LayoutDecision`, роль detector и основные зависимости scoring/dictionary/ngram/resolver.
- В `LearningCache` задокументирована UI-модель learned entries и injectable init.
- В `RetypeDispatcher` задокументирована cooldown-модель single/sequence retype и связи с app state/hotkey undo.
- В `SequenceDetector` задокументированы pending candidates, lookahead thresholds, ingest/reset contract.

**Результат проверки:**
- `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` — 254 теста в 38 наборах, `** TEST SUCCEEDED **`.

**Вывод:** detector/pipeline support слой стал понятнее для сопровождения: теперь документированы основные причины решений, границы cooldown и coalescing многословных retype-блоков.

### Шаг 96. DocC-документация для сервисного слоя и DI-side effects

**Дата:** 2026-05-15

**Цель шага:** продолжить закрывать пробелы в Swift DocC-документации вокруг сервисов, которые взаимодействуют с macOS API и поэтому особенно зависят от явных DI-контрактов.

**Что изменено:**
- В `OnboardingCompletionStore` задокументирован injectable persistence initializer.
- В `LaunchAtLoginManager` задокументированы ServiceManagement side-effect closures и logger.
- В `InputSourceManager` задокументированы typealias-контракты для TIS providers/selectors/observers, а также observer handle и injected dependencies.
- В `CarbonHotkeyManager` задокументированы Carbon handler/hotkey reference state, action dispatch и modifier conversion.
- В `NotificationManager` задокументированы notification-center side-effect closures, pending notification ID и deterministic ID factory.

**Результат проверки:**
- `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` — 254 теста в 38 наборах, `** TEST SUCCEEDED **`.

**Вывод:** сервисный слой стал прозрачнее для сопровождения: теперь явно видно, какие зависимости являются production side effects, а какие заменяются тестовыми closures.

### Шаг 97. DocC-документация для UI/controller и hotkey helper слоя

**Дата:** 2026-05-15

**Цель шага:** продолжить закрывать пробелы в Swift DocC-документации в слое, который связывает SwiftUI/AppKit UI, menu bar item и настройку горячих клавиш.

**Что изменено:**
- В `StatusItemController` задокументированы ownership `NSStatusItem`, зависимости меню, secure/presentation badge state, navigation callbacks, динамическое обновление меню и action handlers.
- В `SettingsWindowController`, `HelpWindowController` и `OnboardingWindowController` уточнены lifecycle/ownership комментарии для lazy singleton окон и injected state.
- В `HotkeyRegistry` задокументированы persisted payload keys, current binding storage, `HotkeyDefinition` fields и modifier flags.
- В `KeyRecorderView` задокументированы SwiftUI/AppKit bridge points, recording state, one-shot event monitor и commit callback.

**Результат проверки:**
- `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` — 254 теста в 38 наборах, `** TEST SUCCEEDED **`.

**Вывод:** UI/controller слой стал понятнее для сопровождения: теперь лучше описаны границы ответственности menu bar controller, оконных controller-ов и hotkey recording/registry инфраструктуры.

### Шаг 98. DocC-документация для settings tab state contracts

**Дата:** 2026-05-15

**Цель шага:** продолжить закрывать пробелы в Swift DocC-документации на уровне SwiftUI settings tabs, где важно понимать источники состояния, binding-и и injected models.

**Что изменено:**
- В `SettingsView` задокументированы все shared `@Bindable` модели, `learningCache`, `launchAtLoginManager`, `openHelp` и tab container.
- В `GeneralTab` задокументированы состояние приложения, статистика и side-effect service для launch-at-login.
- В `HotkeysTab` задокументированы registry, editing/recording/conflict state и view-model row fields.
- В `LayoutsTab` задокументирован input source manager и identity для `LanguagePair` rows.
- В `ExclusionsTab` задокументированы persisted exclusion model и selected bundle state.

**Результат проверки:**
- `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` — 254 теста в 38 наборах, `** TEST SUCCEEDED **`.

**Вывод:** settings UI стал понятнее для сопровождения: теперь зависимости вкладок и transient UI state описаны явно, без необходимости восстанавливать ownership по телу `body`.

### Шаг 99. DocC-документация для dictionaries/history/help/onboarding UI

**Дата:** 2026-05-15

**Цель шага:** продолжить закрывать пробелы в Swift DocC-документации для оставшихся SwiftUI-facing экранов и helper-ов, которые управляют пользовательскими словарями, историей, справкой и onboarding flow.

**Что изменено:**
- В `DictionariesTab` задокументированы language-specific dictionary dependencies, editor input state и selection state.
- В `HistoryTab` задокументированы recent history model, kind/app filters, injectable clipboard writer, filter enum cases и timestamp/export formatters.
- В `HelpView` задокументирован selected section state.
- В `HelpContent` задокументированы `HelpSection` fields, localized body accessors, supported help languages, active-language resolver, static section registry, markdown loader/cache и bundled loader facade.
- В `OnboardingView` задокументированы onboarding dependencies, completion callback, transient sandbox state и все sequential onboarding steps.

**Результат проверки:**
- `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` — 254 теста в 38 наборах, `** TEST SUCCEEDED **`.

**Вывод:** оставшийся SwiftUI-facing слой стал заметно прозрачнее: теперь documented ownership покрывает словари, историю, help content pipeline и onboarding state machine.

### Шаг 100. Logging/privacy audit и hardening экспорта диагностических логов

**Дата:** 2026-05-15

**Цель шага:** перейти от DocC-проходов к аудиту logging/privacy дисциплины: проверить отсутствие `print`/`NSLog`, использование `os.Logger` и корректность диагностического export path.

**Что проверено:**
- В рабочем коде `LayoutSwitcher/` и тестах не найдено использования `print()` или `NSLog()` для runtime-логирования.
- Runtime-логирование использует `os.Logger` с категориями проекта.
- Интерполируемые значения в логах проекта уже размечены через `privacy: .public`, что соответствует принятому правилу проекта для читаемых Console logs.

**Что изменено:**
- В `DiagnosticsLogExporter` добавлен typed failure `LogShowFailure` для non-zero exit status команды `/usr/bin/log show`.
- Production runner теперь возвращает exported data только если `terminationStatus == 0`; иначе export завершается failure и не маскирует сбой пустым/частичным файлом.
- Чистый helper `checkedOutput(_:terminationStatus:)` сделан `nonisolated`, потому что вызывается из `Task.detached` и не зависит от `@MainActor` состояния.
- В `DiagnosticsLogExporterTests` добавлены проверки successful status и failed status.

**Результат проверки:**
- Targeted: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/DiagnosticsLogExporterTests` — 5 тестов, `** TEST SUCCEEDED **`.
- `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` — 256 тестов в 38 наборах, `** TEST SUCCEEDED **`.

**Вывод:** logging/privacy дисциплина в коде подтверждена, а диагностический экспорт стал надежнее: теперь сбой системной команды `log show` не будет ошибочно считаться успешным экспортом.

### Шаг 101. DI/testability audit для side effects и deterministic LearningCache IDs

**Дата:** 2026-05-15

**Цель шага:** начать отдельный DI/testability-проход после logging/privacy аудита: найти прямые production side effects и убедиться, что они либо уже внедряются через closures, либо закрыть небольшой безопасный пробел.

**Что проверено:**
- `ExclusionList` уже использует injected `localizedNameProvider`; прямой `NSWorkspace.shared` находится только в default production implementation.
- `UserDictionary` уже внедряет filesystem side effects через `storageURLProvider`, `createDirectory`, `fileExists`, `readData`, `writeData`; существующие тесты это подтверждают.
- В `LearningCache` обнаружен небольшой DI-пробел: `LearnedEntry.id` создавался через прямой `UUID()`, что усложняло детерминированную проверку UI entry identity.

**Что изменено:**
- В `LearningCache` добавлен injected `makeEntryID` closure с production default `UUID.init`.
- `LearningCache.LearnedEntry.id` теперь передается явно при построении UI-модели.
- В `LearningCacheTests` добавлен тест `allEntriesUsesInjectedIDFactory`, который проверяет детерминированный ID без реального UUID side effect.

**Результат проверки:**
- Targeted: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/LearningCacheTests` — 9 тестов, `** TEST SUCCEEDED **`.
- `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` — 257 тестов в 38 наборах, `** TEST SUCCEEDED **`.

**Вывод:** DI/testability слой стал чуть строже: `LearningCache` теперь полностью детерминируем в тестах не только по storage/clock, но и по generated UI identity.

### Шаг 102. DI/testability audit для PresentationModeDetector

**Дата:** 2026-05-15

**Цель шага:** продолжить DI/testability-проход для production-компонентов, которые читают runtime-состояние macOS.

**Что проверено:** `PresentationModeDetector` уже использует инъекцию `frontmostBundleIDProvider` и `presentationBundleIDs`, поэтому тесты не зависят от реального `NSWorkspace.shared` и текущего активного приложения.

**Что изменено:** provider активного bundle id явно помечен как `@MainActor`, включая stored closure и параметр initializer. Это делает контракт Swift 6 честнее: доступ к `NSWorkspace.shared.frontmostApplication` и тестовые stubs выполняются в той же main-actor изоляции, что и сам detector.

**Результат проверки:**

- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/PresentationModeDetectorTests` — `** TEST SUCCEEDED **`, 5 тестов.
- `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` — `** TEST SUCCEEDED **`, 257 тестов в 38 suites.

**Вывод:** поведение suppression для презентационных приложений не изменено, но dependency-injection контракт стал точнее для Swift 6 strict concurrency и безопаснее для дальнейших тестовых сценариев.

### Шаг 103. Swift 6 actor-contract audit для KeyboardEventTap

**Дата:** 2026-05-15

**Цель шага:** проверить самый близкий к macOS runtime слой обработки клавиатурных событий: event tap, hotkey routing, synthetic-event filter и передачу событий в pipeline.

**Что проверено:** `KeyboardEventTap` сохраняет синхронный callback path через `MainActor.assumeIsolated`, что важно для корректного подавления hotkey events: если заменить это на асинхронный `Task`, событие уже успеет пройти в систему до решения hotkey handler. Также проверены существующие тесты на hotkey consumption, passthrough, autorepeat, synthetic events и disabled tap events.

**Что изменено:** closure properties `onKeyEvent` и `hotkeyHandler` явно помечены как `@MainActor`. Это не меняет runtime-поведение, но фиксирует реальный контракт: обработчики вызываются из main-run-loop callback после проверки main thread и main-actor bridge.

**Результат проверки:**

- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/KeyboardEventTapTests` — `** TEST SUCCEEDED **`, 5 тестов.
- `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` — `** TEST SUCCEEDED **`, 257 тестов в 38 suites.

**Вывод:** event tap сохранил прежнее поведение, а границы Swift 6 actor isolation стали точнее. Это снижает риск случайного подключения обработчиков, которые подразумевают выполнение вне main actor.

### Шаг 104. Lifecycle и actor-contract audit для FocusedAppObserver

**Дата:** 2026-05-15

**Цель шага:** проверить runtime-наблюдатель активного приложения, который поставляет `bundleID`, `localizedName` и secure-field state в pipeline.

**Что проверено:** `FocusedAppObserver` уже имел хорошие DI-границы: `roleProvider`, `currentAppSnapshotProvider`, `observeWorkspaceActivation` и `removeWorkspaceObserver` передаются через initializer, поэтому тесты не зависят от реального `NSWorkspace` и AX subsystem.

**Что изменено:**

- `onChange`, `WorkspaceActivationObserver` и `removeWorkspaceObserver` явно зафиксированы как `@MainActor` callbacks.
- `start()` стал idempotent через внутренний `isStarted`, чтобы повторный вызов не регистрировал второй workspace observer и не создавал дублирующие callbacks.
- Добавлен тест `startIsIdempotentAndDoesNotRegisterDuplicateObservers`.

**Результат проверки:**

- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/FocusedAppObserverTests` — `** TEST SUCCEEDED **`, 6 тестов.
- `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` — `** TEST SUCCEEDED **`, 258 тестов в 38 suites.

**Вывод:** observer стал безопаснее при повторном lifecycle-вызове и точнее по Swift 6 actor isolation. Поведение публикации начального snapshot и обработки activation events сохранено.

### Шаг 105. Lifecycle и actor-contract audit для SecureInputObserver

**Дата:** 2026-05-15

**Цель шага:** проверить runtime-наблюдатель secure input state, который сообщает UI и pipeline, что macOS временно перехватила глобальный поток клавиатурных событий.

**Что проверено:** `SecureInputObserver` уже имел хорошие DI-границы: `secureInputStatusProvider` и `pollingTimerFactory` инжектируются через initializer, а `start()` / `stop()` уже покрывали базовую idempotency.

**Что изменено:**

- `onChange` явно помечен как `@MainActor`, чтобы callback-контракт соответствовал фактической main-actor изоляции observer.
- Добавлен тест `startAfterStopCreatesNewPollingToken`, который подтверждает корректный lifecycle restart: после `stop()` следующий `start()` создает новый polling token и оба token корректно инвалидируются.

**Результат проверки:**

- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/SecureInputObserverTests` — `** TEST SUCCEEDED **`, 4 теста.
- `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` — `** TEST SUCCEEDED **`, 259 тестов в 38 suites.

**Вывод:** secure-input observer сохранил прежнее поведение, но его callback isolation стал точнее для Swift 6, а lifecycle restart теперь закреплен тестом.

### Шаг 106. DI и lifecycle audit для AccessibilityPermission

**Дата:** 2026-05-15

**Цель шага:** проверить boundary вокруг macOS Accessibility trust: чтение текущего статуса, запрос системного prompt, открытие System Settings и polling во время onboarding.

**Что проверено:** `AccessibilityPermission` уже имел хорошие DI-границы: `trustStatusProvider`, `trustPromptRequester`, `systemSettingsOpener` и `pollingTimerFactory` передаются через initializer. `onTrustGranted` уже был явно `@MainActor`, а базовая idempotency `startPolling()` / `stopPolling()` была покрыта тестом.

**Что изменено:**

- Polling interval вынесен в initializer как `pollingInterval` с production default `1.0`.
- `PollingTimerFactory` теперь получает `TimeInterval` явно, вместо скрытой константы внутри default closure.
- Существующий тест polling дополнен проверкой default interval forwarding.
- Добавлен тест `startAfterStopCreatesNewPollingTokenWithInjectedInterval`, который подтверждает корректный restart lifecycle и передачу кастомного interval в новый polling token.

**Результат проверки:**

- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/AccessibilityPermissionTests` — `** TEST SUCCEEDED **`, 6 тестов.
- `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` — `** TEST SUCCEEDED **`, 260 тестов в 38 suites.

**Вывод:** Accessibility trust polling стал более явно конфигурируемым и лучше тестируемым без изменения production default. Lifecycle restart после `stopPolling()` теперь закреплен отдельным тестом.

### Шаг 107. Idempotency audit для LaunchAtLoginManager

**Дата:** 2026-05-15

**Цель шага:** проверить boundary вокруг macOS `SMAppService` для автозапуска при входе в систему.

**Что проверено:** `LaunchAtLoginManager` уже использует DI для `statusProvider`, `registerService` и `unregisterService`, поэтому тесты не вызывают реальный `SMAppService`.

**Что изменено:**

- `setEnabled(true)` теперь возвращает `true` без вызова `registerService`, если статус уже `.enabled`.
- `setEnabled(false)` теперь возвращает `true` без вызова `unregisterService`, если статус уже `.notRegistered`.
- Добавлены тесты `setEnabledIsNoOpWhenAlreadyEnabled` и `setDisabledIsNoOpWhenAlreadyNotRegistered`.

**Результат проверки:**

- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/LaunchAtLoginManagerTests` — `** TEST SUCCEEDED **`, 9 тестов.
- `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` — `** TEST SUCCEEDED **`, 262 теста в 38 suites.

**Вывод:** менеджер автозапуска стал idempotent: не вызывает лишние ServiceManagement side effects, когда нужное состояние уже достигнуто.

### Шаг 108. Idempotency audit для OnboardingCompletionStore

**Дата:** 2026-05-15

**Цель шага:** проверить persistence-boundary для признака завершенного onboarding и убрать лишние записи в хранилище.

**Что проверено:** `OnboardingCompletionStore` уже использует DI для чтения и записи состояния onboarding, поэтому тесты не зависят от реального `UserDefaults`.

**Что изменено:**

- `markCompleted()` теперь не вызывает `writeCompleted(true)`, если onboarding уже отмечен завершенным.
- Добавлен тест `markCompletedDoesNotWriteWhenAlreadyCompleted`, фиксирующий idempotent-поведение.

**Результат проверки:**

- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/OnboardingCompletionStoreTests` — `** TEST SUCCEEDED **`, 3 теста.
- `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` — `** TEST SUCCEEDED **`, 263 теста в 38 suites.

**Вывод:** store стал более аккуратным по side effects: повторное завершение onboarding больше не порождает лишнюю запись в persistence-layer.

### Шаг 109. Explicit result audit для DiagnosticsLogExporter

**Дата:** 2026-05-15

**Цель шага:** улучшить recoverable error handling в boundary, который экспортирует системные логи для диагностики.

**Что проверено:** `DiagnosticsLogExporter` уже использует DI для запуска `log show` и записи файла, поэтому тесты не зависят от реального `/usr/bin/log` и файловой системы.

**Что изменено:**

- Добавлен `ExportResult` с явным результатом `.success` / `.failure(...)`.
- Добавлен `ExportFailureReason` с отдельными причинами `logShowFailed` и `writeFailed`.
- Старый `export(to:) -> Bool` сохранен как compatibility-wrapper для существующих UI call sites.
- Тесты теперь проверяют не только boolean-результат, но и конкретную причину recoverable failure.

**Результат проверки:**

- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/DiagnosticsLogExporterTests` — `** TEST SUCCEEDED **`, 6 тестов.
- `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` — `** TEST SUCCEEDED **`, 264 теста в 38 suites.

**Вывод:** диагностика стала ближе к проектному правилу error handling: recoverable failure больше не сводится только к `Bool`, а имеет явную доменную причину без ломки текущего публичного поведения.

### Шаг 110. Concurrency и test coverage audit для NotificationManager

**Дата:** 2026-05-15

**Цель шага:** усилить boundary вокруг `UNUserNotificationCenter`: явно зафиксировать main-actor side effects и покрыть notification-поведение отдельными deterministic tests.

**Что проверено:** `NotificationManager` уже использует DI для `UNUserNotificationCenter` side effects, но отдельного тестового файла для этого сервиса не было.

**Что изменено:**

- Для injected closures добавлены typealias-ы с явной `@MainActor` изоляцией: delegate setter, authorization requester, category registrar, notification request sender, delivered-notification remover и deterministic ID factory.
- Добавлен `NotificationManagerTests` на ключевые сценарии без обращения к реальному notification center.
- Тестами зафиксированы: установка delegate, запрос authorization через injected requester, регистрация auto-switch категории с Undo action, deterministic notification request, idempotent clear pending notification и безопасная обработка ошибки отправки notification.

**Результат проверки:**

- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/NotificationManagerTests` — `** TEST SUCCEEDED **`, 6 тестов.
- `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` — `** TEST SUCCEEDED **`, 270 тестов в 39 suites.

**Вывод:** notification boundary стал лучше защищен под Swift 6 strict concurrency и получил самостоятельное покрытие, не зависящее от реальных macOS notification permissions.

### Шаг 111. Concurrency и test coverage audit для SoundFeedbackPlayer

**Дата:** 2026-05-15

**Цель шага:** усилить небольшой feedback-boundary вокруг системного звука и зафиксировать deterministic-поведение через тесты.

**Что проверено:** `SoundFeedbackPlayer` уже использует injected closure вместо прямой зависимости в тестируемом path, но closure не был явно `@MainActor`, а отдельного тестового файла для sound feedback не было.

**Что изменено:**

- Добавлен `PlaySound` typealias с явной `@MainActor` изоляцией для injected sound side effect.
- Добавлен `SoundFeedbackPlayerTests`.
- Тестами зафиксированы: вызов injected closure при включенном feedback, отсутствие вызова при disabled-state и непустые локализованные названия `SoundFeedbackKind`.

**Результат проверки:**

- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/SoundFeedbackPlayerTests` — `** TEST SUCCEEDED **`, 3 теста.
- `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` — `** TEST SUCCEEDED **`, 273 теста в 40 suites.

**Вывод:** sound feedback boundary стал явнее для Swift 6 strict concurrency и получил самостоятельное покрытие без обращения к реальному `NSSound`.

### Шаг 112. Dependency Injection и test coverage audit для CapsLockGuard

**Дата:** 2026-05-15

**Цель шага:** убрать прямую зависимость тестируемой логики от реального Caps Lock / IOKit состояния и покрыть restore-сценарии deterministic-тестами.

**Что проверено:** `CapsLockGuard` напрямую читал `CGEventSource.flagsState` и вызывал IOKit (`IOServiceGetMatchingService`, `IOServiceOpen`, `IOHIDSetModifierLockState`), поэтому поведение нельзя было надежно проверить без системного состояния.

**Что изменено:**

- Добавлены `ReadCapsLockState` и `SetCapsLockState` typealias-ы с явной `@MainActor` изоляцией.
- `CapsLockGuard` получил initializer с injected closures для чтения и установки Caps Lock state.
- Production path сохранен через default implementations `liveReadCapsLockState` и `liveSetCapsLockState`.
- Добавлен `CapsLockGuardTests`.
- Тестами зафиксированы: no-op при выключенном Caps Lock, disable/restore при включенном Caps Lock, отсутствие restore после failed disable и idempotent `restore()`.

**Результат проверки:**

- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/CapsLockGuardTests` — `** TEST SUCCEEDED **`, 4 теста.
- `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` — `** TEST SUCCEEDED **`, 277 тестов в 41 suites.

**Вывод:** Caps Lock boundary стал соответствовать DI-паттерну проекта: системные IOKit side effects остались в live defaults, а доменное поведение guard теперь проверяется без реального состояния клавиатуры.

## Шаг 113. Аудит `SyntheticEventFilter`: явная граница синтетических событий

Дата: 2026-05-15

### Что проверено

- Проверен низкоуровневый фильтр синтетических `CGEvent`, которым приложение помечает собственные события перед повторным вводом текста.
- Убедились, что внешний код не зависит от конкретного magic-token: маркер теперь скрыт как `private static let` внутри `SyntheticEventFilter`.
- Добавлены отдельные Swift Testing тесты для трех базовых инвариантов: обычное событие не считается синтетическим, помеченное событие распознается как синтетическое, а сама пометка не меняет тип события.
- Первый точечный прогон поймал корректную Swift 6 проблему изоляции в новых тестах: обращения к `SyntheticEventFilter` должны выполняться из `@MainActor` контекста. Тестовый struct помечен `@MainActor`, после чего проверка стала детерминированной.

### Что изменено

- `LayoutSwitcher/EventTap/SyntheticEventFilter.swift`: magic-token сделан приватной деталью реализации.
- `LayoutSwitcherTests/SyntheticEventFilterTests.swift`: добавлены тесты поведения фильтра синтетических событий.

### Результат проверки

- Targeted: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/SyntheticEventFilterTests` — `** TEST SUCCEEDED **`, 3 теста.
- Build: `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- Full suite: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` — `** TEST SUCCEEDED **`, 280 тестов в 42 suites.

### Вывод

Контур синтетических событий стал чуть безопаснее: внутренний маркер больше не является частью внешнего API, а базовое поведение фильтра теперь покрыто отдельными тестами. Это снижает риск случайной поломки защиты от feedback loop в event tap и retype-сценариях.

## Шаг 114. Аудит `AXElementBridge`: тестовая защита вокруг Accessibility bridge

Дата: 2026-05-15

### Что проверено

- Проверен низкоуровневый мост `CFTypeRef` → `AXUIElement`, который централизует единственный небезопасный `unsafeDowncast` для Accessibility API.
- Production-код уже содержит правильную защиту через `CFGetTypeID(value) == AXUIElementGetTypeID()`, поэтому runtime-поведение не изменялось.
- Добавлены отдельные Swift Testing тесты, фиксирующие два ключевых инварианта: настоящий `AXUIElement` проходит проверку, посторонние Core Foundation значения отвергаются до небезопасного приведения типа.

### Что изменено

- `LayoutSwitcherTests/AXElementBridgeTests.swift`: добавлен новый suite с 3 тестами для `AXElementBridge`.

### Результат проверки

- Targeted: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/AXElementBridgeTests` — `** TEST SUCCEEDED **`, 3 теста.
- Build: `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- Full suite: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` — `** TEST SUCCEEDED **`, 283 теста в 43 suites.

### Вывод

Граница вокруг Accessibility bridge стала надежнее документирована тестами. Это важно, потому что `unsafeDowncast` остается допустимым только при сохранении предварительной проверки Core Foundation type ID; теперь этот контракт защищен регрессией.

## Шаг 115. Аудит `KeyCodeEncoder`: детерминированные тесты без зависимости от системных раскладок

Дата: 2026-05-15

### Что проверено

- Проверен `KeyCodeEncoder`, который подбирает `keyCode` и modifier flags для символа через Carbon `UCKeyTranslate`.
- Найдена проблема качества тестов: `KeyCodeEncoderTests` зависели от реальных системных keyboard layouts через `InputSourceManager`. Это нарушало правило проекта о том, что тесты не должны зависеть от состояния macOS, установленных раскладок или пользовательского окружения.
- Production-поведение сохранено: публичный вызов `KeyCodeEncoder.encode(_:layoutData:)` по умолчанию продолжает использовать `LMGetKbdType()` и `UCKeyTranslate`.
- Для тестов добавлена инъекция `keyboardType` и `keyTranslator`, чтобы проверять алгоритм перебора keycode/modifier combinations через детерминированные stubs.
- Swift 6 проверка поймала два полезных нюанса во время targeted-прогона: `KeyTranslator` должен явно быть `@MainActor`, а Carbon status constants в тестовом stub должны возвращаться как `OSStatus`.

### Что изменено

- `LayoutSwitcher/EventTap/KeyCodeEncoder.swift`: добавлен internal `KeyTranslator`, параметры `keyboardType` и `keyTranslator` с production defaults; default translator вызывает `UCKeyTranslate`.
- `LayoutSwitcherTests/KeyCodeEncoderTests.swift`: системно-зависимые проверки заменены на 5 детерминированных тестов с injected translator.

### Результат проверки

- Targeted: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/KeyCodeEncoderTests` — после исправления Swift 6 isolation/type issues: `** TEST SUCCEEDED **`, 5 тестов.
- Build: `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- Full suite: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` — `** TEST SUCCEEDED **`, 283 теста в 43 suites.

### Вывод

`KeyCodeEncoder` стал лучше соответствовать правилам проекта по DI и тестируемости: side-effect boundary вокруг Carbon теперь можно стабильно тестировать без реальных системных раскладок. Это снижает риск flaky-тестов на разных машинах и одновременно делает Swift 6 isolation-контракт translator-а явным.

## Шаг 116. Аудит `SmartPaste`: проверка side effects без реального pasteboard и раскладок

Дата: 2026-05-15

### Что проверено

- Проверен `SmartPaste`, который читает clipboard, определяет язык текста, при необходимости переключает input source и отправляет синтетический `⌘V`.
- Production-код уже использует DI для pasteboard, key posting и sleep, поэтому runtime-поведение не менялось.
- Найден пробел в тестовом контракте: существующие тесты проверяли язык и факт paste, но почти не фиксировали side effects вокруг layout switching.
- Добавлены проверки двух важных сценариев: когда текущая раскладка уже целевая, `select` и `refresh` не вызываются; когда целевая русская раскладка отличается от текущей, вызывается `select`, затем `refresh`, добавляется pre-paste delay и отправляется `⌘V`.
- `FakeInputSources` расширен счетчиком `refreshCount`, чтобы тесты могли проверять refresh side effect без обращения к реальной системе.

### Что изменено

- `LayoutSwitcherTests/FakeInputSources.swift`: добавлен `refreshCount`, `refresh()` теперь увеличивает счетчик вместо пустого no-op.
- `LayoutSwitcherTests/SmartPasteTests.swift`: добавлен tracking injected sleep durations и 2 новых теста для layout switching/no-switching сценариев.

### Результат проверки

- Targeted: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/SmartPasteTests` — `** TEST SUCCEEDED **`, 8 тестов.
- Build: `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- Full suite: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` — `** TEST SUCCEEDED **`, 285 тестов в 43 suites.

### Вывод

`SmartPaste` стал лучше защищен тестами на уровне side effects. Теперь проверяется не только результат определения языка, но и фактический контракт переключения раскладки: отсутствие лишнего switch при уже подходящей раскладке и корректный switch/refresh/delay перед синтетическим paste при смене языка.

## Шаг 117. Аудит `SelectionConverter`: детерминированное покрытие clipboard fallback

Дата: 2026-05-15

### Что проверено

- Проверен `SelectionConverter`, который выполняет ручную конвертацию выделенного текста: сначала через Accessibility selected text, затем через clipboard fallback.
- Production-код уже имеет DI для focused AX element, pasteboard read/write, key posting и sleep, поэтому runtime-поведение не менялось.
- Найден пробел: для `SelectionConverter` не было отдельного test suite, хотя компонент управляет несколькими side effects (`⌘C`, чтение clipboard, запись конвертированного текста, `⌘V`, восстановление исходного clipboard).
- Добавлены тесты clipboard fallback без реального Accessibility, pasteboard и keyboard events: успешная конвертация `ghbdtn` → `привет`, отсутствие selection после `⌘C`, слишком длинное выделение.
- Проверено, что успешный fallback выполняет ожидаемую последовательность: `Cmd+C`, задержка, запись конвертированного текста, `Cmd+V`, задержка, восстановление исходного clipboard.

### Что изменено

- `LayoutSwitcherTests/SelectionConverterTests.swift`: добавлен новый suite с 3 тестами для clipboard fallback `SelectionConverter`.

### Результат проверки

- Targeted: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/SelectionConverterTests` — `** TEST SUCCEEDED **`, 3 теста.
- Build: `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` — `** BUILD SUCCEEDED **`.
- Full suite: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` — `** TEST SUCCEEDED **`, 288 тестов в 44 suites.

### Вывод

`SelectionConverter` получил базовую защиту самого рискованного fallback-пути без обращения к реальному clipboard или AX. Это снижает риск регрессий в ручной конвертации выделенного текста и подтверждает, что исходный clipboard восстанавливается после успешной вставки.

## Шаг 118. Аудит SelectionConverter: отказ от лишней вставки и restore без исходного clipboard

Дата: 2026-05-15

Цель шага: закрыть два краевых сценария clipboard fallback в `SelectionConverter`, которые важны для пользовательской безопасности: не вставлять текст, если конвертация фактически ничего не изменила, и не восстанавливать clipboard, если до операции исходного значения не было.

Что изменено:

- В `LayoutSwitcherTests/SelectionConverterTests.swift` добавлен тест `clipboardFallbackDoesNotPasteWhenConversionDoesNotChangeText()`.
- В `LayoutSwitcherTests/SelectionConverterTests.swift` добавлен тест `clipboardFallbackSkipsRestoreWhenOriginalClipboardIsNil()`.
- Production-код `LayoutSwitcher/Mapping/SelectionConverter.swift` не изменялся: текущая реализация уже корректно проходит оба сценария.

Проверенные гарантии:

- Если clipboard fallback получил выделенный текст, но конвертация не изменила значение, результат остается `.failure(.conversionFailed)`, запись в clipboard не выполняется и вставка не отправляется.
- Если исходный clipboard был пустым (`nil`), успешная конвертация вставляет исправленный текст, но не делает лишний restore-запись после операции.
- Оба сценария проверяют не только результат, но и фактические side effects: отправленные клавиши, записи в clipboard и контролируемые задержки.

Результаты проверки:

- Targeted: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/SelectionConverterTests` -> `** TEST SUCCEEDED **`, 5 тестов в 1 suite.
- Build: `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` -> `** BUILD SUCCEEDED **`.
- Full suite: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` -> `** TEST SUCCEEDED **`, 290 тестов в 44 suites.

Вывод: clipboard fallback в `SelectionConverter` теперь лучше защищен тестами от двух регрессий: случайной вставки неизмененного текста и лишнего восстановления пустого исходного clipboard. Это повышает доверие к ручной конвертации выделения без расширения production-поверхности.

## Шаг 119. Аудит HotkeyRegistry: читаемое отображение Smart Paste hotkey

Дата: 2026-05-15

Цель шага: убрать небольшой UX-дефект в отображении дефолтного хоткея Smart Paste. Действие `smartPaste` использует virtual key code `9`, но `HotkeyDefinition.displayText` не имел человекочитаемого имени для этой клавиши и мог показывать пользователю техническое `k9` вместо `V`.

Что изменено:

- В `LayoutSwitcher/Hotkeys/HotkeyRegistry.swift` добавлено отображение key code `9` как `V`.
- В `LayoutSwitcherTests/HotkeyRegistryTests.swift` добавлен тест `smartPasteDefaultBindingDisplaysReadableKeyName()`.

Проверенные гарантии:

- Дефолтный хоткей Smart Paste теперь отображается как `⌃⌥⌘V`, а не как `⌃⌥⌘k9`.
- Тест фиксирует именно пользовательскую строку `displayText`, а не только внутренний key code.
- Изменение не затрагивает matching, persistence или конфликтную логику хоткеев.

Результаты проверки:

- Targeted: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/HotkeyRegistryTests` -> `** TEST SUCCEEDED **`, 11 тестов в 1 suite.
- Build: `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` -> `** BUILD SUCCEEDED **`.
- Full suite: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` -> `** TEST SUCCEEDED **`, 291 тест в 44 suites.

Вывод: настройки хоткеев стали понятнее для пользователя, а регрессия в отображении Smart Paste теперь прикрыта автоматическим тестом. Это маленькое исправление, но оно снижает ощущение «сырости» интерфейса настроек.

## Шаг 120. Аудит HotkeyRegistry: поведенческая фиксация Smart Paste hotkey

Дата: 2026-05-15

Цель шага: дополнить предыдущую UX-правку для Smart Paste поведенческой проверкой. После того как отображение `⌃⌥⌘V` стало человекочитаемым, важно зафиксировать, что тот же дефолтный shortcut действительно матчится как действие `.smartPaste`.

Что изменено:

- В `LayoutSwitcherTests/HotkeyRegistryTests.swift` добавлен тест `defaultSmartPasteBindingMatchesControlOptionCommandV()`.
- Production-код не изменялся: текущая логика matching уже корректно обрабатывает `Control + Option + Command + V`.

Проверенные гарантии:

- Событие `keyDown` с key code `9` и модификаторами `Control + Option + Command` возвращает `.smartPaste`.
- Тест закрывает поведенческую сторону дефолтного Smart Paste hotkey, а предыдущий шаг закрывает пользовательское отображение `displayText`.
- Matching, persistence и обработка конфликтов хоткеев остались без изменений.

Результаты проверки:

- Targeted: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/HotkeyRegistryTests` -> `** TEST SUCCEEDED **`, 12 тестов в 1 suite.
- Build: `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` -> `** BUILD SUCCEEDED **`.
- Full suite: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` -> `** TEST SUCCEEDED **`, 292 теста в 44 suites.

Вывод: дефолтный Smart Paste hotkey теперь защищен с двух сторон: пользователь видит корректное `⌃⌥⌘V`, а `HotkeyRegistry` гарантированно сопоставляет это сочетание с `.smartPaste`.

## Шаг 121. Аудит HotkeyRegistry: защита локализованных title/subtitle действий

Дата: 2026-05-15

Цель шага: закрепить качество пользовательского интерфейса настроек хоткеев. Для каждого `HotkeyAction` важно иметь не пустые и реально локализованные title/subtitle, иначе пользователь может увидеть сырой ключ вида `settings.hotkeys...`.

Что изменено:

- В `LayoutSwitcherTests/HotkeyRegistryTests.swift` добавлен тест `allHotkeyActionsHaveLocalizedTitleAndSubtitle()`.
- Production-код не изменялся: текущие локализации уже корректно покрывают все действия хоткеев.

Проверенные гарантии:

- Все действия из `HotkeyAction.ordered` имеют непустой `localizedTitle`.
- Все действия из `HotkeyAction.ordered` имеют непустой `localizedSubtitle`.
- Title/subtitle не возвращаются как сырой localization key с префиксом `settings.hotkeys.`.
- Проверка дополняет предыдущие шаги по Smart Paste: теперь слой хоткеев защищен не только по matching/displayText, но и по пользовательским текстам.

Результаты проверки:

- Targeted: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/HotkeyRegistryTests` -> `** TEST SUCCEEDED **`, 13 тестов в 1 suite.
- Build: `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` -> `** BUILD SUCCEEDED **`.
- Full suite: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` -> `** TEST SUCCEEDED **`, 293 теста в 44 suites.

Вывод: пользовательские тексты действий хоткеев теперь защищены от регрессии локализации. Это снижает риск увидеть в настройках технические ключи вместо понятных названий и описаний.

## Шаг 122. Аудит локализаций: структурная проверка hotkey-ключей в Localizable.xcstrings

Дата: 2026-05-15

Цель шага: закрыть релизный риск, при котором настройки хоткеев в одной из поддерживаемых локалей могут показать пустую строку или сырой ключ локализации. Runtime-тесты уже проверяют текущую локаль, но не гарантируют полноту `.xcstrings` для `en`, `ru`, `ro`, `uk`.

Что изменено:

- Добавлен новый файл `LayoutSwitcherTests/LocalizationCatalogTests.swift`.
- Новый тест `hotkeyActionKeysAreTranslatedForSupportedLanguages()` читает `LayoutSwitcher/Localizable.xcstrings` как JSON-каталог.
- Production-код не изменялся: текущий каталог локализаций уже содержит корректные значения для проверяемых ключей.

Проверенные гарантии:

- Hotkey title/subtitle ключи присутствуют в `Localizable.xcstrings`.
- Для каждого hotkey title/subtitle ключа есть переводы для `en`, `ru`, `ro`, `uk`.
- Каждая проверяемая строка имеет состояние `translated`.
- Значение перевода не пустое и не равно сырому localization key.

Результаты проверки:

- Targeted: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/LocalizationCatalogTests` -> `** TEST SUCCEEDED **`, 1 тест в 1 suite.
- Build: `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` -> `** BUILD SUCCEEDED **`.
- Full suite: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` -> `** TEST SUCCEEDED **`, 294 теста в 45 suites.

Вывод: слой локализации для настроек хоткеев теперь защищен не только runtime-проверками, но и прямой структурной проверкой `.xcstrings` по всем поддерживаемым языкам. Это снижает риск регрессии при добавлении новых действий или обновлении переводов перед релизом.

## Шаг 123. Аудит локализаций: полнота системных InfoPlist-строк

Дата: 2026-05-15

Цель шага: закрыть системный релизный риск, при котором macOS может показывать пустые или непереведенные значения имени bundle/copyright в свойствах приложения, Finder или системных диалогах.

Что изменено:
- В `LayoutSwitcherTests/LocalizationCatalogTests.swift` добавлен тест `infoPlistKeysAreTranslatedForSupportedLanguages()`.
- В `LayoutSwitcher/InfoPlist.xcstrings` заполнены `CFBundleName` для `en`, `ru`, `ro`, `uk`.
- В `LayoutSwitcher/InfoPlist.xcstrings` заполнен `NSHumanReadableCopyright` для `en`, `ru`, `ro`, `uk`.
- Строки переведены в состояние `translated`.

Найденная проблема:
- `CFBundleName` был только в `en` со state `new`.
- `NSHumanReadableCopyright` был пустым и не имел переводов для `ru`, `ro`, `uk`.

Проверенные гарантии:
- Все ключи `InfoPlist.xcstrings` имеют непустые значения для `en`, `ru`, `ro`, `uk`.
- Все проверяемые stringUnit имеют state `translated`.
- Системные строки приложения больше не остаются в состоянии `new` или пустыми.

Результаты проверки:
- Targeted: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/LocalizationCatalogTests` -> `** TEST SUCCEEDED **`, 2 теста в 1 suite.
- Build: `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` -> `** BUILD SUCCEEDED **`.
- Full suite: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` -> `** TEST SUCCEEDED **`, 295 тестов в 45 suites.

Вывод: системные строки приложения теперь локализованы и защищены тестом от возврата пустых/новых значений в `InfoPlist.xcstrings`.

## Шаг 124. Аудит локализаций: защита от неиспользуемых Localizable-ключей

Дата: 2026-05-15

Цель шага: уменьшить шум в `Localizable.xcstrings` и добавить регрессионную защиту от накопления мертвых пользовательских строк.

Что изменено:
- В `LayoutSwitcherTests/LocalizationCatalogTests.swift` добавлен тест `localizableKeysAreReferencedByApplicationSources()`.
- Тест проверяет, что каждый ключ из `Localizable.xcstrings` либо явно используется в Swift-исходниках приложения, либо относится к разрешенному динамическому пространству ключей.
- Для динамической справки явно разрешен префикс `help.section.`, потому что `HelpContent` строит ключи через `help.section.\(id)`.
- Из `LayoutSwitcher/Localizable.xcstrings` удалены 13 подтвержденных неиспользуемых ключей.

Удаленные ключи:
- `%@ (%@)`
- `%@ → %@`
- `%@ ↔ %@`
- `detection.both`
- `detection.dict-hit`
- `detection.ngram`
- `onboarding.hotkeys.convert-selection`
- `onboarding.hotkeys.manual-toggle`
- `onboarding.hotkeys.snooze`
- `onboarding.hotkeys.undo`
- `statusitem.menu.auto-switch-failed`
- `statusitem.menu.recent-switches`
- `statusitem.menu.undo-last`

Проверенные гарантии:
- Новые неиспользуемые ключи в `Localizable.xcstrings` будут обнаруживаться targeted-тестом.
- Динамические help-ключи не дают ложноположительного падения теста.
- Каталог локализаций компилируется после чистки.

Результаты проверки:
- Targeted: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/LocalizationCatalogTests` -> `** TEST SUCCEEDED **`, 3 теста в 1 suite.
- Build: `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` -> `** BUILD SUCCEEDED **`.
- Full suite: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` -> `** TEST SUCCEEDED **`, 296 тестов в 45 suites.

Вывод: `Localizable.xcstrings` стал чище, а проект получил автоматическую защиту от повторного накопления мертвых локализационных ключей.

## Шаг 125. Аудит локализаций: проверка Swift-ссылок на существующие ключи

Дата: 2026-05-15

Цель шага: закрыть обратный риск локализационного каталога — ситуацию, когда Swift-код ссылается на `String(localized:)` ключ, отсутствующий в `Localizable.xcstrings`.

Что изменено:
- В `LayoutSwitcherTests/LocalizationCatalogTests.swift` добавлен тест `applicationLocalizedStringKeysExistInCatalog()`.
- Добавлен helper `applicationSourceText()`, чтобы оба локализационных теста использовали один способ чтения Swift-исходников приложения.
- Добавлены helper-методы `localizedStringKeys(in:)` и `stringLiterals(in:)`, которые извлекают literal-ключи из вызовов `String(localized:)`.
- Тест учитывает и простые вызовы `String(localized: "key")`, и выражения с несколькими literal-ключами внутри аргумента, например ternary-выбор ключа.
- Динамические вызовы без literal-ключей не проверяются этим тестом, чтобы не создавать ложные падения.

Проверенные гарантии:
- Каждый literal-ключ, переданный в `String(localized:)` в Swift-коде приложения, существует в `Localizable.xcstrings`.
- Если UI-код начнет ссылаться на удаленный или забытый ключ, targeted-тест упадет с точным именем ключа.
- Предыдущая гарантия от неиспользуемых ключей сохранена.

Результаты проверки:
- Targeted: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/LocalizationCatalogTests` -> `** TEST SUCCEEDED **`, 4 теста в 1 suite.
- Build: `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` -> `** BUILD SUCCEEDED **`.
- Full suite: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` -> `** TEST SUCCEEDED **`, 297 тестов в 45 suites.

Вывод: локализационный слой теперь защищен в обе стороны: каталог не должен накапливать мертвые ключи, а Swift-код не должен ссылаться на отсутствующие пользовательские строки.

## Шаг 126. Стабилизация unit-тестов: отключение live side effects AppDelegate под XCTest

Дата: 2026-05-15

Цель шага: убрать системные побочные эффекты из unit-test окружения. До правки тестовый host запускал `AppDelegate.applicationDidFinishLaunching`, из-за чего во время unit suite поднимались live-подсистемы приложения: Carbon hotkeys, notifications, focused-app observer, secure-input observer и global event tap.

Что изменено:
- В `LayoutSwitcher/App/AppDelegate.swift` добавлено раннее определение XCTest-окружения через `XCTestConfigurationFilePath` и наличие класса `XCTestCase`.
- `applicationDidFinishLaunching(_:)` теперь сразу выходит под XCTest и не запускает live app startup side effects.
- В `LayoutSwitcherTests/AppDelegateTests.swift` добавлен тест `applicationLaunchSkipsLiveServicesUnderXCTest()`.
- Тест проверяет, что при запуске launch-пути под XCTest не стартует `KeyboardEventTap` и не создается `StatusItemController`.

Почему это важно:
- Unit-тесты больше не зависят от реального Accessibility-состояния macOS.
- Unit-тесты не регистрируют global event tap и Carbon hotkeys через основной AppDelegate.
- Unit-тесты не дергают запросы notification authorization через основной launch-путь.
- Логи тестов стали чище: вместо старта приложения фиксируется `XCTest launch detected; skipping live app startup side effects`.

Проверенные гарантии:
- Production launch path не меняется: guard срабатывает только в XCTest-окружении.
- AppDelegate можно безопасно инстанцировать и вызывать в unit-тесте без live-системных side effects.
- Существующие тесты продолжают проходить.

Результаты проверки:
- Targeted: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/AppDelegateTests` -> `** TEST SUCCEEDED **`, 1 тест в 1 suite.
- Build: `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` -> `** BUILD SUCCEEDED **`.
- Full suite: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` -> `** TEST SUCCEEDED **`, 298 тестов в 46 suites.

Вывод: unit-test окружение стало безопаснее и стабильнее: основной AppDelegate больше не запускает системные подсистемы приложения при прогоне тестов.

## Шаг 127. Оптимизация тестов и runtime: кэширование словарей

Дата: 2026-05-15

Цель шага: убрать повторную тяжелую загрузку словарей при создании `LayoutDetector.defaultMultilingual()` и ускорить unit-test suite без изменения поведения детектора.

Найденная проблема:
- `BundledDictionaryLoader.loadOrEmbedded(language:)` каждый раз заново читал bundled `.txt`-ресурсы словарей.
- `EmbeddedDictionaries.english()/russian()/ukrainian()/romanian()` каждый раз создавали новый `InMemoryDictionary` из больших массивов fallback-корпуса.
- В тестах это приводило к многократным логам вида `Loaded ... words for ...` и заметно увеличивало время полного suite.

Что изменено:
- В `LayoutSwitcher/Dictionary/BundledDictionaryLoader.swift` добавлен read-only cache `cachedFallbacks` для `en`, `ru`, `uk`, `ro`.
- В `LayoutSwitcher/Dictionary/EmbeddedDictionaries.swift` добавлены cached instances для embedded fallback-словарей.
- `InMemoryDictionary` в `LayoutSwitcher/Dictionary/WordDictionary.swift` помечен как `@unchecked Sendable`, потому что объект immutable: язык и normalized word set задаются только в initializer и дальше не мутируют.
- В `LayoutSwitcherTests/DictionaryTests.swift` добавлен тест `bundledFallbacksAreCachedPerLanguage()`.

Почему это безопасно:
- `InMemoryDictionary` не содержит изменяемого состояния после инициализации.
- Возврат одного и того же immutable-экземпляра не меняет результаты `contains(_:)` или `size`.
- Кэш расположен на уровне fallback-словарей, а пользовательские словари остаются динамическими и не кэшируются этим изменением.

Проверенные гарантии:
- `BundledDictionaryLoader.loadOrEmbedded(language:)` возвращает один и тот же экземпляр для повторных запросов одного языка.
- Embedded fallback-словари также не пересоздаются на каждый вызов.
- Полный suite сохранил поведение детектора и pipeline.

Результаты проверки:
- Targeted: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS' -only-testing:LayoutSwitcherTests/DictionaryTests` -> `** TEST SUCCEEDED **`, 6 тестов в 1 suite.
- Build: `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'` -> `** BUILD SUCCEEDED **`.
- Full suite: `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'` -> `** TEST SUCCEEDED **`, 299 тестов в 46 suites, test run после старта Swift Testing прошел за 2.283 секунды.

Вывод: словари теперь загружаются один раз на процесс и переиспользуются как immutable dependencies. Это снижает шум в логах и ускоряет тестовый прогон без изменения пользовательского поведения.

## Шаг 128. Документирование Sendable-инварианта и прямой тест embedded-кэша

**Наблюдение:** после кэширования словарей важно, чтобы архитектурная причина `@unchecked Sendable` была видна прямо в коде, а cached behavior `EmbeddedDictionaries` проверялся напрямую, не только через `BundledDictionaryLoader`.

**Изменения:**
- добавлен DocC-комментарий к `InMemoryDictionary`, фиксирующий инвариант неизменяемости после инициализации;
- добавлен тест `embeddedDictionariesAreCachedPerLanguage`, проверяющий повторное использование экземпляров для `en`, `ru`, `uk`, `ro`;
- сохранен existing fallback-cache test для `BundledDictionaryLoader`.

**Ожидаемый эффект:** меньше риска случайно вернуть дорогое пересоздание больших словарей и понятнее основание для Swift 6 `Sendable`-безопасности.

**Статус:** verified. Targeted DictionaryTests: `** TEST SUCCEEDED **`, 7 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 300 tests / 46 suites.

## Шаг 129. Кэширование RomanianDiacriticResolver для user dictionary path

**Наблюдение:** `LayoutDetector.defaultMultilingual(user...)` пересоздавал `RomanianDiacriticResolver` из полного embedded-словаря Romanian плюс user dictionary при каждом обращении к provider. Это дорого: embedded Romanian corpus содержит большой набор слов, а resolver строит индекс вариантов по plain key.

**Изменения:**
- добавлен `RomanianDiacriticResolverCache`, изолированный на `@MainActor`;
- кэш хранит snapshot последнего набора user words;
- resolver и plain overrides пересобираются только когда `userRomanian.words` реально меняется;
- `LayoutDetector.defaultMultilingual(user...)` теперь использует один cache instance для `romanianDiacriticResolverProvider` и `romanianPlainOverrideProvider`;
- добавлен тест `romanianDiacriticResolverCacheRebuildsOnlyAfterUserWordsChange`.

**Ожидаемый эффект:** меньше CPU/allocations при включенных Romanian diacritics без потери behavior, где user dictionary может обновиться уже после создания detector.

**Статус:** verified. Первый targeted run поймал compile-error `[String]` vs `Set<String>` в default argument; исправлено через `Set(EmbeddedDictionaries.romanian().allWords)`. Targeted LayoutDetectorTests: `** TEST SUCCEEDED **`, 25 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 301 tests / 46 suites.

## Шаг 130. Автоматический guard против force operations в Swift-коде

**Наблюдение:** ручная проверка не нашла `try!`, `as!`, force unwrap в рабочем коде и тестах; единственное совпадение было в комментарии теста про строку `z!`. Так как `AGENTS.md` запрещает force unwrap, этот стандарт лучше закрепить автоматическим тестом.

**Изменения:**
- добавлен `SwiftSafetyRulesTests`;
- тест сканирует production sources в `LayoutSwitcher`;
- расширение guard на `LayoutSwitcherTests` временно отложено: targeted-прогон показал legacy force unwraps в старых test fixtures, это отдельный cleanup-пласт;
- перед анализом удаляются комментарии и строковые литералы, чтобы не ловить false positive из текста/примеров;
- проверяются `try!`, `as!` и postfix force unwrap.

**Ожидаемый эффект:** будущие нарушения safety rule будут ловиться в regression suite до попадания в сборку/релиз.

**Статус:** verified. Первый широкий targeted run обнаружил, что application sources уже чистые, а legacy test fixtures еще содержат force unwraps; guard ограничен production sources. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 1 test / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 302 tests / 47 suites.

## Шаг 131. Уточнение Swift safety scanner для prefix-negation

**Наблюдение:** при попытке расширить guard на тестовые файлы scanner создавал false positives для обычной prefix-негации (`!flag`, `#expect(!value.isEmpty)`, `!(...)`). Это могло привести к бессмысленным правкам тестов вместо реального удаления force unwrap.

**Изменения:**
- уточнено правило postfix force unwrap: `!` считается нарушением только после выражения-терминатора (`letter`, `number`, `_`, `)`, `]`);
- `try!` и `as!` остаются отдельными нарушениями и больше не дублируются как force unwrap;
- добавлен self-test `scannerIgnoresPrefixNegationAndFindsForceOperations`.

**Ожидаемый эффект:** safety guard становится точнее и пригоднее для постепенного расширения на `LayoutSwitcherTests` без шума от валидного Swift-кода.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 2 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 303 tests / 47 suites.

## Шаг 132. Расширение force-operation guard на тестовый код

**Наблюдение:** после уточнения scanner прямой поиск не показал реальных postfix force unwrap в `LayoutSwitcherTests`; предыдущие срабатывания были false positives на prefix-негацию. Значит guard можно безопасно расширить с production sources на тестовый код.

**Изменения:**
- `SwiftSafetyRulesTests.swiftSourcesDoNotUseForceOperations` теперь сканирует `LayoutSwitcher` и `LayoutSwitcherTests`;
- self-test scanner остается в suite и защищает от регресса в распознавании prefix negation vs postfix force unwrap.

**Ожидаемый эффект:** весь Swift-код проекта, включая тесты, теперь автоматически защищен от `try!`, `as!` и postfix force unwrap.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 2 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 303 tests / 47 suites.

## Шаг 133. Guard против runtime-trap API

**Наблюдение:** после защиты проекта от force operations стоит так же автоматически запрещать crash-only API (`fatalError`, `preconditionFailure`, `assertionFailure`). Для пользовательского приложения такие вызовы ухудшают отказоустойчивость и противоречат курсу на явную обработку ошибок.

**Изменения:**
- `SwiftSafetyRulesTests` получил тест `swiftSourcesDoNotUseRuntimeTrapAPIs`;
- guard сканирует `LayoutSwitcher` и `LayoutSwitcherTests`;
- перед анализом удаляются комментарии и строковые литералы, чтобы не ловить false positive из документации или self-test fixtures.

**Ожидаемый эффект:** будущие runtime traps будут ловиться regression suite до попадания в приложение.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 3 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 304 tests / 47 suites.

## Шаг 134. Guard против неконтролируемых задержек в тестах

**Наблюдение:** правила проекта требуют детерминированные тесты без `Thread.sleep` и неконтролируемых задержек. Такие вызовы часто приводят к флейкам: локально тест проходит, а на другой машине или под нагрузкой падает.

**Изменения:**
- `SwiftSafetyRulesTests` получил тест `testsDoNotUseUncontrolledSleepAPIs`;
- guard сканирует `LayoutSwitcherTests`;
- перед анализом удаляются комментарии и строковые литералы, чтобы не ловить false positive из документации или fixtures;
- запрещены прямые вызовы `Thread.sleep`, `Task.sleep`, `Task<Never, Never>.sleep`, `usleep`, `nanosleep`.

**Ожидаемый эффект:** новые тесты будут использовать injected sleep closures, controlled clocks или `ControlledEvaluationDelay`, а не реальные задержки времени.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 4 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 305 tests / 47 suites.

## Шаг 135. Guard против XCTest API в unit-тестах

**Наблюдение:** правила проекта закрепляют Swift Testing как основной framework для unit-тестов. Если новые тесты начнут использовать `XCTest`, suite станет менее единообразным: появятся разные assertion-style, разные lifecycle-паттерны и больше риска случайно обойти `@MainActor struct` convention.

**Изменения:**
- `SwiftSafetyRulesTests` получил тест `unitTestsDoNotUseXCTestAPIs`;
- guard сканирует только `LayoutSwitcherTests`, не затрагивая отдельный UI-test target;
- перед анализом удаляются комментарии и строковые литералы;
- запрещены `import XCTest`, `XCTAssert*`, `XCTFail`, `XCTUnwrap`.

**Ожидаемый эффект:** новые unit-тесты будут оставаться на Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`), а XCTest не вернется в core test suite случайно.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 5 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 306 tests / 47 suites.

## Шаг 136. Guard против console logging в production-коде

**Наблюдение:** правила проекта требуют использовать `os.Logger` для логирования. Случайные `print`, `debugPrint`, `dump`, `NSLog` или `os_log` в production-коде ухудшают управляемость логов и обходят принятый privacy/logging style.

**Изменения:**
- `SwiftSafetyRulesTests` получил тест `appSourcesUseLoggerInsteadOfConsoleLogging`;
- guard сканирует только production-папку `LayoutSwitcher`;
- перед анализом удаляются комментарии и строковые литералы;
- запрещены прямые console/debug logging вызовы: `print`, `Swift.print`, `debugPrint`, `dump`, `NSLog`, `os_log`.

**Ожидаемый эффект:** новые diagnostic-сообщения будут добавляться через `Logger(subsystem:category:)` и сохранят единый стиль логирования проекта.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 6 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 307 tests / 47 suites.

## Шаг 137. Guard против legacy DispatchQueue scheduling

**Наблюдение:** для Swift 6 strict concurrency важно не возвращаться к неструктурированным GCD-переходам в production-коде. `DispatchQueue.main.async` и `DispatchQueue.global` легко обходят actor isolation и усложняют тестирование, особенно там, где уже принят `@MainActor`/injected clock подход.

**Изменения:**
- `SwiftSafetyRulesTests` получил тест `appSourcesAvoidLegacyDispatchQueueScheduling`;
- guard сканирует только production-папку `LayoutSwitcher`;
- перед анализом удаляются комментарии и строковые литералы;
- запрещены прямые GCD scheduling-вызовы: `DispatchQueue.main.async`, `DispatchQueue.main.asyncAfter`, `DispatchQueue.global`, `DispatchQueue.global().async`.

**Ожидаемый эффект:** новые асинхронные переходы будут оформляться через main-actor isolation, `Task { @MainActor ... }`, injected clocks или controlled async-delay паттерны, а не через GCD.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 7 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 308 tests / 47 suites.

## Шаг 138. Guard против non-ASCII кода вне строк и комментариев

**Наблюдение:** правила проекта разделяют языки: чат, аудит и документация пишутся на русском, а code identifiers, comments и logs должны оставаться English-only. User-facing текст должен жить в локализации, а не в raw Swift-коде.

**Изменения:**
- `SwiftSafetyRulesTests` получил тест `appSourceCodeOutsideStringsAndCommentsIsASCIIOnly`;
- guard сканирует только production-папку `LayoutSwitcher`;
- перед анализом удаляются комментарии и строковые литералы;
- non-ASCII символы запрещены только в оставшемся Swift-коде, поэтому локализация и пользовательские строки не затрагиваются.

**Ожидаемый эффект:** новые идентификаторы, операторы или raw code fragments не будут случайно смешивать языки; пользовательский текст останется в `Localizable.xcstrings`.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 8 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 309 tests / 47 suites.

## Шаг 139. Guard против ObservableObject API в production-коде

**Наблюдение:** проект уже использует современный Observation-подход (`@Observable`, `@Bindable`) вместо `ObservableObject`/`@Published`. Важно не смешивать два поколения state-management API, иначе UI-модели начнут расходиться по стилю, lifecycle и тестируемости.

**Изменения:**
- `SwiftSafetyRulesTests` получил тест `appSourcesUseObservationInsteadOfObservableObject`;
- guard сканирует только production-папку `LayoutSwitcher`;
- перед анализом удаляются комментарии и строковые литералы;
- запрещены `ObservableObject`, `@ObservedObject`, `@StateObject`, `@EnvironmentObject`, `@Published`, `objectWillChange`.

**Ожидаемый эффект:** новые UI-bound модели останутся на `@Observable`, а SwiftUI views будут продолжать использовать современный binding/state pattern без возврата к Combine-era API.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 9 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 310 tests / 47 suites.

## Шаг 140. Self-test для sanitizer safety-suite

**Наблюдение:** большинство новых quality-guards сначала удаляют комментарии и строковые литералы, чтобы не ловить false positive из документации, fixtures и локализуемых строк. Значит сам sanitizer стал частью критичной тестовой инфраструктуры.

**Изменения:**
- `SwiftSafetyRulesTests` получил тест `sanitizerRemovesCommentsAndStringLiteralsBeforeRuleScanning`;
- fixture содержит запрещенные tokens внутри comments/string literals;
- тест проверяет, что runtime-trap, console logging, uncontrolled sleep, legacy DispatchQueue и ObservableObject guards не срабатывают на очищенном source.

**Ожидаемый эффект:** если логика sanitizer будет случайно сломана, targeted safety-suite покажет проблему сразу, до появления шумных false positive в остальных guards.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 10 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 311 tests / 47 suites.

## Шаг 141. Positive self-test для rule scanners

**Наблюдение:** safety-suite должен защищать не только от false positive, но и от false negative. Если helper-сканер случайно перестанет находить запрещенный token, основной guard может оставаться зеленым, но уже не будет выполнять свою функцию.

**Изменения:**
- `SwiftSafetyRulesTests` получил тест `scannersFindForbiddenTokensInCode`;
- тест напрямую подает запрещенные tokens в scanners для runtime traps, console logging, uncontrolled sleep, legacy DispatchQueue, XCTest API, ObservableObject API и non-ASCII code;
- проверяется, что каждый scanner возвращает хотя бы одно нарушение на явно плохом source.

**Ожидаемый эффект:** изменения в helper-логике будут ловиться с двух сторон: sanitizer защищен от ложных срабатываний, а scanners теперь защищены от ложных пропусков.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 11 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 312 tests / 47 suites.

## Шаг 142. Guard против `import Combine` в production-коде

**Наблюдение:** проект уже закрепил современный Observation-подход и Swift 6 concurrency guards. Даже если `ObservableObject`/`@Published` запрещены отдельно, случайный `import Combine` в production-коде может стать ранним признаком возврата к Combine-era паттернам.

**Изменения:**
- `SwiftSafetyRulesTests` получил тест `appSourcesDoNotImportCombine`;
- guard сканирует только production-папку `LayoutSwitcher`;
- перед анализом удаляются комментарии и строковые литералы;
- `import Combine` добавлен в sanitizer self-test и positive scanner self-test.

**Ожидаемый эффект:** новые production-файлы будут оставаться на Observation/structured concurrency без случайного подключения Combine.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 12 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 313 tests / 47 suites.

## Шаг 143. Guard против test framework imports в production-коде

**Наблюдение:** production target не должен зависеть от тестовых framework-ов. Даже случайный `import Testing` или `import XCTest` в app source нарушает границу target-ов и может маскировать тестовую инфраструктуру внутри приложения.

**Изменения:**
- `SwiftSafetyRulesTests` получил тест `appSourcesDoNotImportTestFrameworks`;
- guard сканирует только production-папку `LayoutSwitcher`;
- перед анализом удаляются комментарии и строковые литералы;
- `import Testing` и `import XCTest` добавлены в sanitizer self-test и positive scanner self-test.

**Ожидаемый эффект:** тестовые зависимости останутся в `LayoutSwitcherTests`/UI-test target, а production Swift-код сохранит чистую dependency boundary.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 13 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 314 tests / 47 suites.

## Шаг 144. Guard против wall-clock API в unit-тестах

**Наблюдение:** детерминированные тесты не должны зависеть от текущего времени. Прямые `Date()`, `Date.now` и `Calendar.current` делают проверки чувствительными к моменту запуска, timezone/day rollover и CI-нагрузке.

**Изменения:**
- `SwiftSafetyRulesTests` получил тест `unitTestsDoNotUseWallClockAPIs`;
- guard сканирует `LayoutSwitcherTests`;
- перед анализом удаляются комментарии и строковые литералы;
- запрещены прямые `Date()`, `Date.now`, `Calendar.current`;
- wall-clock scanner добавлен в sanitizer self-test и positive scanner self-test;
- `KeyboardEventTap` оставлен как единственное audited exception, потому что CGEvent callback должен принимать hotkey-consume решение синхронно.

**Ожидаемый эффект:** новые unit-тесты будут использовать fixed dates, injected clocks/calendar providers или controlled test fixtures вместо реального времени.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 14 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 315 tests / 47 suites.

## Шаг 145. Guard против random API в unit-тестах

**Наблюдение:** unit-тесты должны быть полностью воспроизводимыми. Прямые `UUID()` и `.random(...)` создают скрытую случайность: тест может проходить локально, но стать нестабильным в CI или при параллельных запусках.

**Изменения:**
- `SwiftSafetyRulesTests` получил тест `unitTestsDoNotUseRandomAPIs`;
- guard сканирует `LayoutSwitcherTests`;
- перед анализом удаляются комментарии и строковые литералы;
- запрещены прямые `UUID()`, `UUID().uuidString` и `.random(...)`;
- random scanner добавлен в sanitizer self-test и positive scanner self-test;
- `RecentSwitchesTests.makeDefaults` больше не использует `UUID().uuidString`, а строит suite name от текущего test-функции и очищает persistent domain.

**Ожидаемый эффект:** новые unit-тесты будут использовать фиксированные значения или injected ID/value factories вместо случайных данных.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 15 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 316 tests / 47 suites.

## Шаг 146. Guard против `@unchecked Sendable`

**Наблюдение:** `@unchecked Sendable` отключает часть гарантий Swift 6 strict concurrency и переносит ответственность за потокобезопасность на разработчика. Такой обход допустим только после отдельного аудита, но не должен появляться случайно.

**Изменения:**
- `SwiftSafetyRulesTests` получил тест `swiftSourcesDoNotUseUncheckedSendable`;
- guard сканирует `LayoutSwitcher` и `LayoutSwitcherTests`;
- перед анализом удаляются комментарии и строковые литералы;
- запрещено прямое использование `@unchecked Sendable`;
- scanner добавлен в sanitizer self-test и positive scanner self-test.

**Ожидаемый эффект:** новые обходы Swift concurrency safety будут блокироваться тестами до попадания в проект.

**Статус:** verified. Targeted DictionaryTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 29 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 323 tests / 47 suites.

## Шаг 153. Явная actor-isolation для unstructured `Task`

**Наблюдение:** аудит Swift concurrency показал, что почти все unstructured `Task` в app-коде уже явно указывают `@MainActor`, но экспорт логов из `SettingsView` запускался через голый `Task { ... }`. Для Swift 6 такой код менее очевиден: он может полагаться на inherited actor context и усложняет будущий аудит UI-side effects.

**Изменения:**
- `SettingsView.exportLogs()` теперь запускает export closure как `Task { @MainActor in ... }`;
- `SwiftSafetyRulesTests` получил guard `appSourcesUseExplicitActorOnUnstructuredTasks`;
- scanner разрешает `Task.detached` и actor-annotated tasks, но запрещает `Task { ... }` / `Task(priority:) { ... }` без явного actor в app sources;
- sanitizer fixture дополнен комментарием с `Task { ... }`, чтобы правило не срабатывало на comments/strings.

**Ожидаемый эффект:** unstructured tasks в production-коде становятся audit-friendly: actor boundary виден прямо в месте запуска, а новые неявные `Task` будут пойманы тестом.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 23 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 324 tests / 47 suites.

## Шаг 154. Value semantics для `PresentationModeDetector`

**Наблюдение:** `PresentationModeDetector` не хранит изменяемое состояние, не требует identity и работает как небольшой вычислительный сервис поверх injected `frontmostBundleIDProvider` и immutable set bundle identifiers. Объявление `final class` противоречило правилу проекта `prefer struct by default`.

**Изменения:**
- `PresentationModeDetector` переведен с `final class` на `struct`;
- публичный контракт и DI initializer сохранены без изменения поведения;
- `SwiftSafetyRulesTests` получил guard `swiftSourcesKeepPresentationModeDetectorValueTyped`;
- scanner запрещает возврат `class PresentationModeDetector` / `final class PresentationModeDetector` после удаления comments/strings.

**Ожидаемый эффект:** presentation-mode detection остается детерминированным и тестируемым, но больше не несет лишнюю reference semantics. Новые изменения не смогут случайно вернуть detector к reference type без падения safety-suite.

**Статус:** verified. Targeted PresentationModeDetectorTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 29 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 325 tests / 47 suites.

## Шаг 155. Value semantics для `LearningCache`

**Наблюдение:** `LearningCache` работал как wrapper вокруг injected `UserDefaults`, clock и ID factory. Собственного mutable identity у типа нет: записи читаются и пишутся через computed persistence property, а все side effects уже проходят через initializer dependencies. Поэтому `final class` был лишней reference semantics.

**Изменения:**
- `LearningCache` переведен с `final class` на `struct`;
- публичные методы и initializer сохранены без изменения поведения;
- `SwiftSafetyRulesTests` получил guard `swiftSourcesKeepLearningCacheValueTyped`;
- scanner запрещает возврат `class LearningCache` / `final class LearningCache` после удаления comments/strings.

**Ожидаемый эффект:** learning cache остается детерминированным persistence adapter, но лучше соответствует правилу проекта `prefer struct by default`. Случайный возврат к reference type будет пойман safety-suite.

**Статус:** verified. Targeted LearningCacheTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 34 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 326 tests / 47 suites.

## Шаг 156. Подключение `detectionSensitivity` к runtime detection

**Наблюдение:** настройка чувствительности детектора сохранялась в `AppState` и была доступна в UI, но runtime-вызовы `LayoutDetector.decide(...)` не передавали соответствующие `DetectionThresholds`. В результате выбор Conservative/Balanced/Aggressive мог не менять фактическое поведение автопереключения.

**Изменения:**
- `LayoutDetector.decide(...)` получил optional `thresholds` override с сохранением прежнего default behavior;
- `TypingPipeline` передает `appState.detectionSensitivity.thresholds` в auto-switch и auto-extend decisions;
- `ManualActionsCoordinator` передает те же thresholds в manual retype и sentence conversion decisions;
- `LayoutDetectorTests` получил регрессионный тест, где aggressive thresholds меняют n-gram fallback decision;
- `SwiftSafetyRulesTests` получил guard `appSourcesPassSensitivityThresholdsToDetectorDecisions`, запрещающий production-вызовы `detector.decide(...)` без `thresholds:`.

**Ожидаемый эффект:** пользовательская настройка чувствительности становится реально рабочей в auto и manual detection paths; новые вызовы detector-а не смогут обойти sensitivity без падения safety-suite.

**Статус:** verified. Targeted LayoutDetectorTests + SwiftSafetyRulesTests + TypingPipelineTests: `** TEST SUCCEEDED **`, 76 tests / 3 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 328 tests / 47 suites.

## Шаг 157. Value semantics для `LayoutDetector`

**Наблюдение:** после подключения `detectionSensitivity` через explicit `thresholds` override сам `LayoutDetector` больше не требует mutable property или reference identity. Алгоритм `decide(...)` является вычислительным сервисом: он получает buffer, active language, feature flags и thresholds, затем возвращает доменное решение без side effects.

**Изменения:**
- `LayoutDetector` переведен с `final class` на `struct`;
- stored `thresholds` стал immutable `let`;
- публичный initializer и factories `defaultMultilingual(...)` сохранены без изменения поведения;
- `SwiftSafetyRulesTests` получил guard `swiftSourcesKeepLayoutDetectorValueTyped`;
- scanner запрещает возврат `class LayoutDetector` / `final class LayoutDetector` после удаления comments/strings.

**Ожидаемый эффект:** detector соответствует правилу проекта `prefer struct by default`, а sensitivity thresholds остаются явной immutable частью конфигурации. Случайный возврат к reference type будет пойман safety-suite.

**Статус:** verified. Targeted LayoutDetectorTests + SwiftSafetyRulesTests + TypingPipelineTests: `** TEST SUCCEEDED **`, 77 tests / 3 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 329 tests / 47 suites.

## Шаг 158. Value semantics для `CompositeDictionary`

**Наблюдение:** `CompositeDictionary` не владеет mutable state и не требует identity: он хранит immutable `language` и immutable список `parts`, а затем делегирует `contains(_:)` и `size` underlying dictionaries. Reference semantics здесь были лишними, особенно после перевода dictionary-related services к value semantics.

**Изменения:**
- `CompositeDictionary` переведен с `final class` на `struct`;
- initializer и `WordDictionary` conformance сохранены без изменения поведения;
- `SwiftSafetyRulesTests` получил guard `swiftSourcesKeepCompositeDictionaryValueTyped`;
- scanner запрещает возврат `class CompositeDictionary` / `final class CompositeDictionary` после удаления comments/strings.

**Ожидаемый эффект:** composition layer для словарей больше не создает лишнюю reference identity; future regressions будут ловиться safety-suite.

**Статус:** verified. Targeted DictionaryTests + LayoutDetectorTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 61 tests / 3 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 330 tests / 47 suites.

## Шаг 159. Value semantics для `LaunchAtLoginManager`

**Наблюдение:** `LaunchAtLoginManager` не хранит mutable state и не требует object identity. Он является thin service wrapper над injected `SMAppService` side-effect closures: `statusProvider`, `registerService`, `unregisterService`. Такое поведение лучше выражается value semantics.

**Изменения:**
- `LaunchAtLoginManager` переведен с `final class` на `struct`;
- initializer, `isEnabled` и `setEnabled(_:)` сохранены без изменения поведения;
- `SwiftSafetyRulesTests` получил guard `swiftSourcesKeepLaunchAtLoginManagerValueTyped`;
- scanner запрещает возврат `class LaunchAtLoginManager` / `final class LaunchAtLoginManager` после удаления comments/strings.

**Ожидаемый эффект:** launch-at-login wiring остается полностью инъектируемым и тестируемым, но больше не создает лишнюю reference identity.

**Статус:** verified. Targeted LaunchAtLoginManagerTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 38 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 331 tests / 47 suites.

## Шаг 160. Value semantics для `SmartPaste`

**Наблюдение:** `SmartPaste` не владеет mutable state и не требует object identity. Сервис хранит injected dependencies (`InputSourceManaging`, clipboard reader, key-event poster, sleep closure), вычисляет язык clipboard и выполняет side effects через эти зависимости.

**Изменения:**
- `SmartPaste` переведен с `final class` на `struct`;
- production initializer, test initializer и `paste()` сохранены без изменения поведения;
- `SwiftSafetyRulesTests` получил guard `swiftSourcesKeepSmartPasteValueTyped`;
- scanner запрещает возврат `class SmartPaste` / `final class SmartPaste` после удаления comments/strings.

**Ожидаемый эффект:** smart-paste helper остается полностью инъектируемым service value, без лишней reference identity.

**Статус:** verified. Targeted SmartPasteTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 38 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 332 tests / 47 suites.

## Шаг 158. Value semantics для `CompositeDictionary`

**Наблюдение:** `CompositeDictionary` не владеет mutable state и не требует identity: он хранит immutable `language` и immutable список `parts`, а затем делегирует `contains(_:)` и `size` underlying dictionaries. Reference semantics здесь были лишними, особенно после перевода dictionary-related services к value semantics.

**Изменения:**
- `CompositeDictionary` переведен с `final class` на `struct`;
- initializer и `WordDictionary` conformance сохранены без изменения поведения;
- `SwiftSafetyRulesTests` получил guard `swiftSourcesKeepCompositeDictionaryValueTyped`;
- scanner запрещает возврат `class CompositeDictionary` / `final class CompositeDictionary` после удаления comments/strings.

**Ожидаемый эффект:** composition layer для словарей больше не создает лишнюю reference identity; future regressions будут ловиться safety-suite.

**Статус:** verified. Targeted DictionaryTests + LayoutDetectorTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 61 tests / 3 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 330 tests / 47 suites.

## Шаг 159. Value semantics для `LaunchAtLoginManager`

**Наблюдение:** `LaunchAtLoginManager` не хранит mutable state и не требует object identity. Он является thin service wrapper над injected `SMAppService` side-effect closures: `statusProvider`, `registerService`, `unregisterService`. Такое поведение лучше выражается value semantics.

**Изменения:**
- `LaunchAtLoginManager` переведен с `final class` на `struct`;
- initializer, `isEnabled` и `setEnabled(_:)` сохранены без изменения поведения;
- `SwiftSafetyRulesTests` получил guard `swiftSourcesKeepLaunchAtLoginManagerValueTyped`;
- scanner запрещает возврат `class LaunchAtLoginManager` / `final class LaunchAtLoginManager` после удаления comments/strings.

**Ожидаемый эффект:** launch-at-login wiring остается полностью инъектируемым и тестируемым, но больше не создает лишнюю reference identity.

**Статус:** verified. Targeted LaunchAtLoginManagerTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 38 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 331 tests / 47 suites.

## Шаг 147. Guard против unaudited actor isolation bypasses

**Наблюдение:** `MainActor.assumeIsolated` и `nonisolated(unsafe)` обходят нормальные гарантии Swift 6 strict concurrency. Такие инструменты допустимы только как редкое исключение после отдельного аудита; поэтому guard запрещает новые неаудированные использования и оставляет единственное документированное исключение для синхронного CGEvent callback.

**Изменения:**
- `SwiftSafetyRulesTests` получил тест `swiftSourcesDoNotUseUnauditedUnsafeIsolationBypasses`;
- guard сканирует `LayoutSwitcher` и `LayoutSwitcherTests`;
- перед анализом удаляются комментарии и строковые литералы;
- запрещены новые неаудированные `MainActor.assumeIsolated` и `nonisolated(unsafe)`;
- scanner добавлен в sanitizer self-test и positive scanner self-test.

**Ожидаемый эффект:** новые неаудированные обходы actor isolation будут блокироваться тестами до попадания в проект.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 17 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 318 tests / 47 suites.

## Шаг 148. Guard против singleton-style `shared` state

**Наблюдение:** проектный стандарт требует dependency injection вместо собственных singleton/global access points. Определения вида `static let shared` и `static var shared` создают скрытую глобальную зависимость и усложняют тестирование.

**Изменения:**
- `SwiftSafetyRulesTests` получил тест `swiftSourcesDoNotDefineSingletonSharedState`;
- guard сканирует `LayoutSwitcher` и `LayoutSwitcherTests`;
- перед анализом удаляются комментарии и строковые литералы;
- запрещены определения `static let shared` и `static var shared`;
- scanner добавлен в sanitizer self-test и positive scanner self-test.

**Ожидаемый эффект:** новые сервисы и shared-state объекты будут проектироваться через initializer injection/default closures, а не через singleton-доступ.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 18 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 319 tests / 47 suites.

## Шаг 149. Guard против stored `static var` mutable state

**Наблюдение:** после запрета singleton-style `shared` в коде оставался более широкий риск: stored `static var` может становиться скрытым mutable global state даже без имени `shared`. Поиск показал, что вычисляемые `static var` используются безопасно, а единственный stored mutable cache находился в help loader.

**Изменения:**
- `BundledHelpLoader` больше не хранит mutable `static var` loader;
- production help cache заменен на лениво создаваемый immutable snapshot `static let bodiesByLanguage`;
- `HelpBodyLoader` получил явный `bodies(for:)` для повторного использования загрузки/парсинга;
- `SwiftSafetyRulesTests` получил guard `swiftSourcesDoNotDefineStoredStaticMutableState`;
- scanner игнорирует вычисляемые `static var`, но запрещает stored `static var ... = ...` после удаления комментариев и строковых литералов.

**Ожидаемый эффект:** новые mutable global caches и скрытая статическая изменяемость будут останавливаться тестами, а допустимые вычисляемые свойства останутся разрешенными.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 19 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 320 tests / 47 suites.

## Шаг 150. Guard против static `DateFormatter` reference state

**Наблюдение:** аудит `static let` показал, что большинство таких объявлений являются безопасными constants (`Logger`, keys, sets, callbacks). Реальный риск найден в `HistoryTab`: `DateFormatter` является mutable reference type, поэтому `static let DateFormatter` создает общую изменяемую ссылку, даже если само свойство объявлено через `let`.

**Изменения:**
- `HistoryTab.exportPayload` теперь принимает `timestampStringProvider` вместо `DateFormatter`;
- on-screen и export timestamps форматируются без shared static formatter state;
- `HistoryTabTests` используют deterministic closure вместо `DateFormatter` fixture;
- `SwiftSafetyRulesTests` получил guard `swiftSourcesDoNotDefineStaticDateFormatters`;
- scanner запрещает `static let/var` `DateFormatter` после удаления комментариев и строковых литералов.

**Ожидаемый эффект:** в проект не вернутся статические `DateFormatter` instances как скрытое shared mutable reference state; форматирование останется инъектируемым и тестируемым.

**Статус:** verified. Targeted HistoryTabTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 22 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 321 tests / 47 suites.

## Шаг 151. Guard против static `live` service instances

**Наблюдение:** аудит `static let` показал два service-like объявления `static let live` в feedback-компонентах. Даже если сами типы value-like, такая форма создает shared production instance и выглядит как скрытый singleton access point. Для DI-контракта безопаснее использовать factory method и передавать созданную зависимость через initializer.

**Изменения:**
- `SoundFeedbackPlayer.live` заменен на `SoundFeedbackPlayer.live()` factory method;
- `VisualFeedbackPlayer.live` заменен на `VisualFeedbackPlayer.live()` factory method;
- `VisualFeedbackPlayerTests` обновлен на вызов factory method;
- `SwiftSafetyRulesTests` получил guard `swiftSourcesDoNotDefineStaticLiveInstances`;
- scanner запрещает `static let live` после удаления комментариев и строковых литералов.

**Ожидаемый эффект:** production-ready dependencies остаются удобными для wiring, но не хранятся как shared static instances; новые `static let live` будут остановлены тестами.

**Статус:** verified. Targeted SoundFeedbackPlayerTests + VisualFeedbackPlayerTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 27 tests / 3 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 322 tests / 47 suites.

## Шаг 152. Value semantics для `InMemoryDictionary`

**Наблюдение:** аудит dictionary caches показал, что `EmbeddedDictionaries` и `BundledDictionaryLoader` держат `InMemoryDictionary` в `static let` caches. Сам `InMemoryDictionary` был immutable, но объявлен как `final class`, поэтому caches фактически разделяли reference object. Для словаря без identity это лишняя reference semantics и потенциальный скрытый shared-state риск.

**Изменения:**
- `InMemoryDictionary` переведен с `final class` на `struct`;
- тесты словарных caches больше не проверяют identity через `===`;
- `DictionaryTests` теперь проверяют stable value behavior: размеры и lookup-результаты;
- `SwiftSafetyRulesTests` получил guard `swiftSourcesKeepInMemoryDictionaryValueTyped`;
- scanner запрещает возврат `class InMemoryDictionary` / `final class InMemoryDictionary` после удаления комментариев и строковых литералов.

**Ожидаемый эффект:** словарные static caches остаются быстрыми и стабильными, но больше не закрепляют shared reference object; `InMemoryDictionary` соответствует value-semantics правилу проекта.

**Статус:** verified. Targeted DictionaryTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 323 tests / 47 suites.

## Шаг 153. Actor isolation для `SettingsView.exportLogs`

**Наблюдение:** `SettingsView.exportLogs` запускал unstructured `Task` без явной actor-аннотации. Для Swift 6 strict concurrency это риск: UI-flow должен оставаться явно привязанным к `MainActor`, особенно когда closure трогает presentation state и вызывает AppKit save panel.

**Изменения:**
- `SettingsView.exportLogs` переведен на `Task { @MainActor in ... }`;
- сохранен существующий user-facing flow экспорта diagnostics logs;
- `SwiftSafetyRulesTests` получил guard против unstructured `Task { ... }` без явного actor context;
- sanitizer и positive scanner self-tests покрывают новый запрет.

**Ожидаемый эффект:** новые unstructured tasks в app sources должны явно выбирать actor context, а UI-bound операции не будут случайно уходить в неочевидный executor.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 324 tests / 47 suites.

## Шаг 154. Value semantics для `PresentationModeDetector`

**Наблюдение:** `PresentationModeDetector` выполняет чистую проверку bundle ID against injected/configured set и не требует identity. Reference semantics здесь были избыточны и расходились с правилом проекта `prefer struct by default`.

**Изменения:**
- `PresentationModeDetector` переведен с `final class` на `struct`;
- публичный API и поведение определения presentation apps сохранены;
- `SwiftSafetyRulesTests` получил guard `swiftSourcesKeepPresentationModeDetectorValueTyped`;
- scanner запрещает возврат `class PresentationModeDetector` / `final class PresentationModeDetector` после удаления comments/strings.

**Ожидаемый эффект:** detector остается value-typed utility без скрытой shared identity, а случайный откат к class будет пойман safety-suite.

**Статус:** verified. Targeted PresentationModeDetectorTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 325 tests / 47 suites.

## Шаг 155. Value semantics для `LearningCache`

**Наблюдение:** `LearningCache` хранит injected persistence closures и предоставляет cache-like API, но не нуждается в reference identity. Единственная mutation-точка была совместима с value semantics через `nonmutating set`, потому что фактический side effect делегируется injected closure.

**Изменения:**
- `LearningCache` переведен с `final class` на `struct`;
- setter сохранен как `nonmutating set`;
- тесты существующего cache behavior сохранены;
- `SwiftSafetyRulesTests` получил guard `swiftSourcesKeepLearningCacheValueTyped`;
- scanner запрещает возврат `class LearningCache` / `final class LearningCache` после удаления comments/strings.

**Ожидаемый эффект:** learning cache остается инъектируемым value service, без лишней object identity и без риска тихого возврата к reference semantics.

**Статус:** verified. Targeted LearningCacheTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 326 tests / 47 suites.

## Шаг 156. Реальное подключение `detectionSensitivity`

**Наблюдение:** настройка `detectionSensitivity` сохранялась в `AppState`, но detector decisions использовали только thresholds, зафиксированные внутри `LayoutDetector`. Это делало UI-настройку чувствительности неполной: пользователь менял режим, но часть detection path продолжала работать по default thresholds.

**Изменения:**
- `LayoutDetector.decide(...)` получил явный optional override `thresholds thresholdOverride: DetectionThresholds? = nil`;
- внутри detector используется локальный `activeThresholds`, который влияет на min/max length, strict min, NaturalLanguage thresholds, active-dictionary override margin и n-gram margin;
- `TypingPipeline` передает `appState?.detectionSensitivity.thresholds ?? detector.thresholds` в auto-switch и auto-extend decisions;
- `ManualActionsCoordinator` передает те же effective thresholds в manual retype и sentence conversion;
- `LayoutDetectorTests` получил regression test `thresholdsOverrideChangesNGramFallbackDecision`;
- `SwiftSafetyRulesTests` получил guard `appSourcesPassSensitivityThresholdsToDetectorDecisions`.

**Ожидаемый эффект:** режимы sensitivity теперь действительно меняют решение detector во всех production decision paths, а новый guard не даст вернуть вызовы `detector.decide(...)` без effective thresholds.

**Статус:** verified. Targeted LayoutDetectorTests + SwiftSafetyRulesTests + TypingPipelineTests: `** TEST SUCCEEDED **`, 76 tests / 3 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 328 tests / 47 suites.

## Шаг 157. Value semantics для `LayoutDetector`

**Наблюдение:** после подключения `detectionSensitivity` через explicit `thresholds` override сам `LayoutDetector` больше не требует mutable property или reference identity. Алгоритм `decide(...)` является вычислительным сервисом: он получает buffer, active language, feature flags и thresholds, затем возвращает доменное решение без side effects.

**Изменения:**
- `LayoutDetector` переведен с `final class` на `struct`;
- stored `thresholds` стал immutable `let`;
- публичный initializer и factories `defaultMultilingual(...)` сохранены без изменения поведения;
- `SwiftSafetyRulesTests` получил guard `swiftSourcesKeepLayoutDetectorValueTyped`;
- scanner запрещает возврат `class LayoutDetector` / `final class LayoutDetector` после удаления comments/strings.

**Ожидаемый эффект:** detector соответствует правилу проекта `prefer struct by default`, а sensitivity thresholds остаются явной immutable частью конфигурации. Случайный возврат к reference type будет пойман safety-suite.

**Статус:** verified. Targeted LayoutDetectorTests + SwiftSafetyRulesTests + TypingPipelineTests: `** TEST SUCCEEDED **`, 77 tests / 3 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 329 tests / 47 suites.

## Шаг 158. Value semantics для `CompositeDictionary`

**Наблюдение:** `CompositeDictionary` не владеет mutable state и не требует identity: он хранит immutable `language` и immutable список `parts`, а затем делегирует `contains(_:)` и `size` underlying dictionaries. Reference semantics здесь были лишними, особенно после перевода dictionary-related services к value semantics.

**Изменения:**
- `CompositeDictionary` переведен с `final class` на `struct`;
- initializer и `WordDictionary` conformance сохранены без изменения поведения;
- `SwiftSafetyRulesTests` получил guard `swiftSourcesKeepCompositeDictionaryValueTyped`;
- scanner запрещает возврат `class CompositeDictionary` / `final class CompositeDictionary` после удаления comments/strings.

**Ожидаемый эффект:** composition layer для словарей больше не создает лишнюю reference identity; future regressions будут ловиться safety-suite.

**Статус:** verified. Targeted DictionaryTests + LayoutDetectorTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 61 tests / 3 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 330 tests / 47 suites.

## Шаг 159. Value semantics для `LaunchAtLoginManager`

**Наблюдение:** `LaunchAtLoginManager` не хранит mutable state и не требует object identity. Он является thin service wrapper над injected `SMAppService` side-effect closures: `statusProvider`, `registerService`, `unregisterService`. Такое поведение лучше выражается value semantics.

**Изменения:**
- `LaunchAtLoginManager` переведен с `final class` на `struct`;
- initializer, `isEnabled` и `setEnabled(_:)` сохранены без изменения поведения;
- `SwiftSafetyRulesTests` получил guard `swiftSourcesKeepLaunchAtLoginManagerValueTyped`;
- scanner запрещает возврат `class LaunchAtLoginManager` / `final class LaunchAtLoginManager` после удаления comments/strings.

**Ожидаемый эффект:** launch-at-login wiring остается полностью инъектируемым и тестируемым, но больше не создает лишнюю reference identity.

**Статус:** verified. Targeted LaunchAtLoginManagerTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 38 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 331 tests / 47 suites.

## Шаг 160. Value semantics для `SmartPaste`

**Наблюдение:** `SmartPaste` не владеет mutable state и не требует object identity. Сервис хранит injected dependencies (`InputSourceManaging`, clipboard reader, key-event poster, sleep closure), вычисляет язык clipboard и выполняет side effects через эти зависимости.

**Изменения:**
- `SmartPaste` переведен с `final class` на `struct`;
- production initializer, test initializer и `paste()` сохранены без изменения поведения;
- `SwiftSafetyRulesTests` получил guard `swiftSourcesKeepSmartPasteValueTyped`;
- scanner запрещает возврат `class SmartPaste` / `final class SmartPaste` после удаления comments/strings.

**Ожидаемый эффект:** smart-paste helper остается полностью инъектируемым service value, без лишней reference identity.

**Статус:** verified. Targeted SmartPasteTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 38 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 332 tests / 47 suites.

## Шаг 161. Value semantics для `SelectionConverter`

**Наблюдение:** `SelectionConverter` не владеет mutable state и не требует object identity. Сервис хранит injected dependencies (`TextConverter`, focused element provider, pasteboard read/write closures, key-event poster, sleep closure) и выполняет conversion side effects только через эти зависимости.

**Изменения:**
- `SelectionConverter` переведен с `final class` на `struct`;
- production initializer, test initializer и `convertSelection()` сохранены без изменения поведения;
- `SwiftSafetyRulesTests` получил guard `swiftSourcesKeepSelectionConverterValueTyped`;
- scanner запрещает возврат `class SelectionConverter` / `final class SelectionConverter` после удаления comments/strings.

**Ожидаемый эффект:** selection-conversion helper остается fully injectable value service без лишней reference identity.

**Статус:** verified. Targeted SelectionConverterTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 36 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 333 tests / 47 suites.

## Шаг 162. Value semantics для `Retyper`

**Наблюдение:** `Retyper` не владеет собственным mutable state и не требует object identity. Он является orchestration service: получает injected dependencies (`KeyboardMapping`, layout providers/selectors, sleep, key-event posters) и делегирует единственный stateful lifecycle `CapsLockGuard`, который остается отдельным identity-объектом для пары capture/restore.

**Изменения:**
- `Retyper` переведен с `final class` на `struct`;
- DI initializer, `retype(...)`, `retypeResult(...)` и `retypeSequenceResult(...)` сохранены без изменения поведения;
- `SwiftSafetyRulesTests` получил guard `swiftSourcesKeepRetyperValueTyped`;
- scanner запрещает возврат `class Retyper` / `final class Retyper` после удаления comments/strings.

**Ожидаемый эффект:** retype orchestration теперь соответствует правилу `prefer struct by default`, а mutable identity остается только там, где она действительно нужна: в `CapsLockGuard`, `RetypeDispatcher`, event/observer lifecycle objects.

**Статус:** verified. Targeted RetyperTests + TypingPipelineTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 63 tests / 3 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 334 tests / 47 suites.

## Шаг 163. Safety guard для `final class` boundary

**Наблюдение:** после серии переводов сервисов на value semantics оставшиеся `class` в app sources в основном являются lifecycle/UI/state objects: `@Observable` models, `NSObject` delegates/controllers, event taps, observers, dispatchers и объекты с mutable identity. Для такого слоя важно запретить случайное появление обычных наследуемых `class`, потому что проектное правило требует `struct` по умолчанию и `final class` только при необходимости identity.

**Изменения:**
- добавлен safety-test `appSourcesKeepReferenceTypesFinal`;
- scanner проходит app sources после удаления comments/strings и ищет `class ...` без `final`;
- sanitizer fixture расширен примером `class NonFinalReferenceType` внутри comment block;
- positive scanner check подтверждает, что `class MutableReference {}` ловится, а `final class StableReference {}` допускается.

**Ожидаемый эффект:** новые reference types больше не смогут появиться в application layer как наследуемые классы по умолчанию. Если identity нужна, разработчик явно пишет `final class`; если не нужна — выбирает `struct`.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 33 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 335 tests / 47 suites.

## Шаг 164. Safety guard для `[weak self]` в `Task` closures

**Наблюдение:** проектное правило требует захватывать `[weak self]` в closure, где используется `self`. Самый рискованный практический случай в текущей архитектуре — unstructured `Task { @MainActor ... }`, потому что такие closures могут пережить вызывающий объект и удержать lifecycle/state owner дольше ожидаемого.

**Изменения:**
- добавлен safety-test `appSourcesCaptureSelfWeaklyInTasks`;
- scanner проходит app sources после удаления comments/strings;
- для каждого `Task { ... }` / `Task(priority:) { ... }` собирается весь closure block, а не только первая строка;
- если block содержит `self.` или `self?`, но не содержит capture-list с `weak self`, тест падает;
- sanitizer fixture и positive scanner checks расширены примерами unsafe/safe Task captures.

**Ожидаемый эффект:** новые async paths не смогут случайно удерживать owner через strong `self` внутри `Task`. Для owner-bound work остается явный паттерн `Task { @MainActor [weak self] in ... }`; для closures без `self` правило не шумит.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 34 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 336 tests / 47 suites.

## Шаг 165. Safety guard для `Logger` interpolation privacy

**Наблюдение:** проектное правило требует использовать `os.Logger` и явно аннотировать пользовательские данные через `privacy: .public`, чтобы логи оставались читаемыми в Console и не превращались в `<private>`. Сейчас production-код уже придерживается этого паттерна, но без safety guard новый interpolation внутри `Self.logger.*(...)` мог появиться без privacy annotation.

**Изменения:**
- добавлен safety-test `appSourcesDeclareLoggerInterpolationPrivacy`;
- scanner проходит app sources и ищет `logger.` calls с Swift string interpolation `\\(...)`;
- каждый interpolation body проверяется на наличие `privacy:`;
- scanner умеет корректно разобрать вложенные parentheses внутри выражения, например `String(describing: value), privacy: .public`;
- positive scanner checks добавлены для unsafe interpolation, обычного `privacy: .public` и вложенного `String(describing:)`.

**Ожидаемый эффект:** новые логи с interpolated значениями не смогут попасть в код без явной privacy annotation. Это закрепляет текущий privacy-first logging стиль проекта автоматическим тестом.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 35 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 337 tests / 47 suites.

## Шаг 166. Safety guard против `TODO` / `FIXME` в app sources

**Наблюдение:** в текущем app layer не найдено открытых `TODO` / `FIXME` markers. Для проекта полезнее хранить технический долг в audit-документе с номером шага, контекстом и статусом, чем оставлять короткие комментарии в коде без владельца и критерия завершения.

**Изменения:**
- добавлен safety-test `appSourcesDoNotLeaveTodoMarkers`;
- scanner проходит Swift-файлы application layer и ищет standalone markers `TODO` / `FIXME`;
- positive scanner checks подтверждают, что оба маркера ловятся;
- нейтральный текст про tracking долга в `Swift6CodeQualityAudit.md` не считается нарушением.

**Ожидаемый эффект:** новые временные комментарии не будут незаметно оседать в production-коде. Если появляется долг, он должен быть либо сразу закрыт, либо явно описан в аудите как отдельный шаг.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 36 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 338 tests / 47 suites.

## Шаг 167. Safety guard для `Logger` subsystem/category

**Наблюдение:** все текущие `Logger(subsystem:category:)` declarations в application layer используют единый subsystem `GIH.LayoutSwitcher`, а category names оформлены в PascalCase. Это соответствует правилам проекта и облегчает фильтрацию логов в Console по subsystem/category.

**Изменения:**
- добавлен safety-test `appSourcesUseConsistentLoggerSubsystemAndCategories`;
- scanner проходит Swift-файлы application layer и ищет `Logger(subsystem: "...", category: "...")` declarations;
- subsystem обязан быть ровно `GIH.LayoutSwitcher`;
- category обязана соответствовать PascalCase pattern;
- positive scanner checks добавлены для неверного subsystem, неверного lowercase category и корректного объявления.

**Ожидаемый эффект:** новые logger declarations не смогут случайно использовать другой subsystem или неструктурированное имя категории. Логи останутся единообразными и удобными для диагностики.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 37 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 339 tests / 47 suites.

## Шаг 168. Safety guard для dot-namespaced `UserDefaults` keys

**Наблюдение:** правила проекта требуют dot-namespaced `UserDefaults` keys, например `settings.autoAddRomanianDiacritics` или `stats.autoTotal`. Текущий код в основном использует constants вида `Self.*Key`, что хорошо для сопровождения, но без safety guard новый direct literal `forKey: "enabled"` или новый `defaultsKey = "enabled"` мог попасть в код незаметно.

**Изменения:**
- добавлен safety-test `appSourcesUseNamespacedUserDefaultsKeys`;
- scanner проверяет direct string literals в `forKey: "..."`;
- scanner проверяет static key constants, которые выглядят как `UserDefaults` keys;
- `legacyDefaultsKey` оставлен явным migration exception, чтобы не ломать чтение старых настроек;
- payload/environment keys исключены из правила, потому что они не являются ключами `UserDefaults`;
- positive scanner checks добавлены для unsafe direct key, unsafe `defaultsKey`, safe namespaced key, legacy exception и `stats.` prefix.

**Ожидаемый эффект:** новые persisted settings/stats keys будут сразу получать namespace. Это снижает риск коллизий между settings, stats, onboarding, history и другими доменами хранения.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 38 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 340 tests / 47 suites.

## Шаг 169. DI boundary для `UserDefaults.standard`

**Наблюдение:** `OnboardingCompletionStore` уже имел injectable closures для deterministic tests, но production defaults внутри closure initializer напрямую ссылались на `UserDefaults.standard`. Это не ломало тестируемость, однако оставляло в app layer явный singleton access и ослабляло правило проекта: side effects должны проходить через initializer injection.

**Изменения:**
- `OnboardingCompletionStore` получил отдельный `init(defaults: UserDefaults = .standard)`;
- closure initializer стал чистым DI initializer без production defaults;
- поведение `OnboardingCompletionStore()` сохранено для `AppDelegate`;
- добавлен safety-test `appSourcesDoNotAccessUserDefaultsStandardDirectly`;
- scanner запрещает прямой `UserDefaults.standard` в app sources, но допускает injected shorthand `.standard` в initializer defaults.

**Ожидаемый эффект:** новые persisted stores не будут незаметно обращаться к `UserDefaults.standard` напрямую. Production dependency остается дефолтной, но проходит через явную точку инъекции, что упрощает тестирование и будущую замену storage backend.

**Статус:** verified. Targeted OnboardingCompletionStoreTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 42 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 341 tests / 47 suites.

## Шаг 170. DI boundary для `FileManager.default` в `UserDictionary`

**Наблюдение:** `UserDictionary` уже был хорошо подготовлен к deterministic tests через injectable storage closures, но production defaults внутри DI initializer напрямую использовали `FileManager.default`. Это повторяло тот же паттерн, что и в шаге 169: тестируемость есть, но singleton access остается внутри app source и может распространяться дальше.

**Изменения:**
- `UserDictionary` получил отдельный production initializer `init(language:storageURL:fileManager:)`;
- файловые операции `createDirectory`, `fileExists`, `urls(for:in:)` теперь завязаны на injected `FileManager`;
- closure initializer стал чистым DI initializer без `FileManager.default` defaults;
- `fileURL(for:fileManager:)` принимает injected `FileManager` и использует shorthand `.default` только на границе production initializer-а;
- `UserDictionaryTests` явно передает storage closures;
- добавлен safety-test `appSourcesDoNotAccessFileManagerDefaultDirectly`.

**Ожидаемый эффект:** новые filesystem-backed services не будут незаметно брать `FileManager.default` напрямую. Production behavior сохранен, но dependency boundary стал явным и совместимым с правилами проекта по DI.

**Статус:** verified. Targeted UserDictionaryTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 42 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 342 tests / 47 suites.

## Шаг 171. DI boundary для `NSWorkspace.shared` в `PresentationModeDetector`

**Наблюдение:** `PresentationModeDetector` уже поддерживал deterministic tests через `frontmostBundleIDProvider`, но production default closure напрямую обращалась к `NSWorkspace.shared`. Это сохраняло скрытую singleton dependency внутри detector-а, хотя сам сервис уже был value-typed и хорошо подходил для явной dependency boundary.

**Изменения:**
- `PresentationModeDetector` получил production initializer `init(workspace:presentationBundleIDs:)`;
- lookup frontmost bundle ID теперь строится от injected `NSWorkspace`;
- initializer с `frontmostBundleIDProvider` стал чистым DI initializer без production default closure;
- поведение `PresentationModeDetector()` сохранено через shorthand `.shared` на границе production initializer-а;
- добавлен safety-test `presentationModeDetectorDoesNotAccessNSWorkspaceSharedDirectly`;
- scanner запрещает прямой `NSWorkspace.shared` именно в `PresentationModeDetector.swift`, не блокируя пока отдельные существующие `NSWorkspace` usage sites в других сервисах.

**Ожидаемый эффект:** detector остается value-typed вычислительным сервисом с явной dependency boundary. Будущий возврат к прямому `NSWorkspace.shared` внутри detector-а будет пойман safety-suite.

**Статус:** verified. Targeted PresentationModeDetectorTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 46 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 343 tests / 47 suites.

## Шаг 172. DI boundary для `NSWorkspace.shared` в `FocusedAppObserver`

**Наблюдение:** `FocusedAppObserver` уже имел injectable closures для current app snapshot, workspace activation observer и observer removal, но production defaults внутри этого же initializer напрямую использовали `NSWorkspace.shared`. Это смешивало production singleton wiring и test DI в одной сигнатуре.

**Изменения:**
- `FocusedAppObserver` получил production initializer `init(roleProvider:workspace:)`;
- current-app snapshot, activation observer и removal теперь строятся от injected `NSWorkspace`;
- closure initializer стал чистым DI initializer без production defaults;
- behavior `FocusedAppObserver()` сохранен через shorthand `.shared` на production boundary;
- добавлен safety-test `focusedAppObserverDoesNotAccessNSWorkspaceSharedDirectly`.

**Ожидаемый эффект:** наблюдение за frontmost app остается полностью тестируемым, а прямой `NSWorkspace.shared` больше не живет внутри runtime observer-а. Будущий откат будет пойман safety-suite.

**Статус:** verified. Targeted FocusedAppObserverTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 48 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 344 tests / 47 suites.

## Шаг 173. DI boundary для `NSWorkspace` lookup в `ExclusionList`

**Наблюдение:** `ExclusionList` уже поддерживал deterministic UI sorting через injected `localizedNameProvider`, но production helper `localizedName(for:)` напрямую использовал `NSWorkspace.shared.urlForApplication(...)`. Это оставляло скрытую workspace dependency внутри списка исключений и усложняло контроль за singleton usage.

**Изменения:**
- `ExclusionList` получил production initializer `init(defaults:workspace:)`;
- initializer с `localizedNameProvider` стал чистым DI initializer без production default closure;
- `localizedName(for:)` теперь принимает injected `NSWorkspace` через параметр helper-а;
- добавлен тест `sortedEntriesUseInjectedLocalizedNameProvider` для явной проверки DI lookup-а;
- добавлен safety-test `exclusionListDoesNotAccessNSWorkspaceSharedDirectly`.

**Ожидаемый эффект:** список исключений сохраняет прежнее production-поведение, но UI name lookup стал явной dependency boundary. Будущий возврат прямого `NSWorkspace.shared` в `ExclusionList.swift` будет пойман safety-suite.

**Статус:** verified. Targeted ExclusionListTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 50 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 346 tests / 47 suites.

## Шаг 174. DI boundary для `NSWorkspace` opener в `AccessibilityPermission`

**Наблюдение:** `AccessibilityPermission` уже имел injectable closures для trust status, permission prompt, opening System Settings и polling timer, но production defaults находились в том же initializer. Из-за этого `systemSettingsOpener` напрямую использовал `NSWorkspace.shared.open(...)`, смешивая production wiring и deterministic DI.

**Изменения:**
- `AccessibilityPermission` получил production initializer `init(pollingInterval:workspace:)`;
- opening System Settings теперь строится от injected `NSWorkspace`;
- trust status, trust prompt и polling timer остались production defaults только на production boundary;
- closure initializer стал чистым DI initializer без production default closures;
- тесты переведены на локальный `makePermission(...)` helper с безопасными stubs;
- добавлен safety-test `accessibilityPermissionDoesNotAccessNSWorkspaceSharedDirectly`.

**Ожидаемый эффект:** permission observer сохраняет прежнее runtime-поведение, но direct workspace singleton больше не находится внутри DI initializer-а. Будущий возврат прямого `NSWorkspace.shared` в `AccessibilityPermission.swift` будет пойман safety-suite.

**Статус:** verified. Targeted AccessibilityPermissionTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 50 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 347 tests / 47 suites.

## Шаг 175. DI boundary для `Bundle.main` в `HelpBodyLoader`

**Наблюдение:** контрольный singleton-scan после закрытия `NSWorkspace.shared` показал прямое чтение `Bundle.main` в `HelpBodyLoader.bundledResource(...)`. Сам loader уже поддерживал injected `ResourceLoader`, но production default resource loader был смешан с DI initializer-ом.

**Изменения:**
- `HelpBodyLoader` получил production initializer `init(bundle:)` с default shorthand `.main`;
- initializer `init(resourceLoader:)` стал чистым DI initializer без production default closure;
- bundled markdown lookup теперь читает resources из injected `Bundle`;
- добавлен safety-test `helpContentDoesNotAccessBundleMainDirectly`;
- scanner получил `bundleMainViolations(...)` и self-check fixtures для `Bundle.main` / `.main`.

**Ожидаемый эффект:** help markdown loader сохраняет прежнее production-поведение, но прямой `Bundle.main` больше не живет внутри resource lookup-а. Будущий откат будет пойман safety-suite.

**Статус:** verified. Targeted HelpContentTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 49 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 348 tests / 47 suites.

## Шаг 176. DI boundary для `UNUserNotificationCenter.current()` в `NotificationManager`

**Наблюдение:** `NotificationManager` уже использовал injectable closures для delegate, authorization, categories, posting и removal, но production defaults внутри DI initializer-а напрямую обращались к `UNUserNotificationCenter.current()`. Это смешивало runtime notification center wiring и deterministic test boundary.

**Изменения:**
- `NotificationManager` получил production initializer `init(notificationCenter:makeNotificationID:)`;
- delegate setup, authorization request, category registration, posting и removal теперь строятся от injected `UNUserNotificationCenter`;
- closure initializer стал чистым DI initializer без production default closures;
- `NotificationManagerTests` переведены на локальный `makeManager(...)` helper с безопасными stubs;
- добавлен safety-test `notificationManagerDoesNotAccessCurrentNotificationCenterDirectly`;
- scanner получил `notificationCenterCurrentViolations(...)` и self-check fixtures для `UNUserNotificationCenter.current()` / `.current()`.

**Ожидаемый эффект:** notification flow сохраняет прежнее production-поведение, но прямой singleton lookup больше не живет внутри testable initializer-а. Будущий откат будет пойман safety-suite.

**Статус:** verified. Targeted NotificationManagerTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 52 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 349 tests / 47 suites.

## Шаг 177. DI boundary для timer/status defaults в `SecureInputObserver`

**Наблюдение:** `SecureInputObserver` уже имел injectable `secureInputStatusProvider` и `pollingTimerFactory`, но production defaults находились прямо в testable initializer-е. Это смешивало Carbon secure-input lookup, real `Timer` wiring и deterministic test boundary.

**Изменения:**
- `SecureInputObserver` получил production initializer `init(interval:)`;
- `IsSecureEventInputEnabled()` и real run-loop `Timer` теперь создаются только на production boundary;
- closure initializer стал чистым DI initializer без production default closures;
- тесты переведены на локальный `makeObserver(...)` helper с безопасными stubs;
- добавлен safety-test `secureInputObserverKeepsInitializerDefaultsOnProductionBoundaryOnly`;
- scanner получил `defaultedInjectedClosureViolations(...)` для защиты от возврата production defaults в DI initializer.

**Ожидаемый эффект:** secure-input observer сохраняет прежнее runtime-поведение, но тестируемый initializer больше не несет скрытых production side effects. Будущий откат будет пойман safety-suite.

**Статус:** verified. Targeted SecureInputObserverTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 51 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 350 tests / 47 suites.

## Шаг 178. Injected delay boundary для `SequenceDetector`

**Наблюдение:** `SequenceDetector` является state machine для coalescing multi-word retype candidates и не должен владеть production timing primitive. До шага в initializer-е был default closure с `Task.sleep(for:)`, из-за чего низкоуровневый detector сам знал о runtime delay implementation.

**Изменения:**
- initializer `SequenceDetector` теперь требует явный `sleepBeforeFlush` без production default;
- production/test delay остается responsibility owner-а (`TypingPipeline`), который уже передает closure при создании detector-а;
- добавлен safety-test `sequenceDetectorDoesNotUseTaskSleepDirectly`;
- guard сканирует `LayoutSwitcher/Pipeline/SequenceDetector.swift` после удаления comments/strings и запрещает возврат `Task.sleep` внутрь detector-а.

**Ожидаемый эффект:** `SequenceDetector` стал более чистым и детерминированным компонентом: он управляет только состоянием pending sequence, а time primitive приходит через DI. Это снижает риск скрытых async side effects и упрощает дальнейшую изоляцию production delay на верхнем boundary.

**Статус:** verified. Targeted TypingPipelineTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 72 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 351 tests / 47 suites.

## Шаг 179. Production delay boundary для `TypingPipeline`

**Наблюдение:** после очистки `SequenceDetector` следующий скрытый production timing primitive оставался в initializer-е `TypingPipeline`: `sleepBeforeSequenceFlush` имел default closure с `Task.sleep(for:)`. Для тестируемого pipeline это лишний side effect default, потому что время sequence lookahead должно приходить через явную DI-зависимость.

**Изменения:**
- `TypingPipeline` теперь требует явные `sleepBeforeSequenceFlush` и `now` без production defaults;
- production `Task.sleep(for:)` и `Date.init` перенесены в `AppDelegate` при сборке runtime pipeline;
- сборка runtime pipeline вынесена в `makePipeline()` вместо прямого `TypingPipeline(...)` в lazy property initializer;
- прямой unit-test setup в `TypingPipelineTests` получил явные deterministic delay и `now`;
- добавлен safety-test `typingPipelineDoesNotUseTaskSleepDirectly`;
- guard сканирует `LayoutSwitcher/Pipeline/TypingPipeline.swift` после удаления comments/strings и запрещает возврат `Task.sleep` внутрь pipeline.

**Ожидаемый эффект:** `TypingPipeline` остается orchestration-компонентом с явной dependency injection для времени, а production sleep находится на app composition boundary. Это уменьшает скрытые async side effects и делает future tests менее зависимыми от wall-clock scheduling.

**Статус:** verified. Targeted TypingPipelineTests + AppDelegateTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 74 tests / 3 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 352 tests / 47 suites.

## Шаг 180. Pure DI boundary для `Retyper`

**Наблюдение:** `Retyper` уже поддерживал injected side effects, но production defaults оставались внутри initializer-а через optional closures: lookup enabled layouts/current layout, layout refresh/select, `Task.sleep(nanoseconds:)`, CGEvent posting и `CapsLockGuard()`. Это смешивало deterministic retype logic и runtime I/O в одном constructor-е.

**Изменения:**
- `Retyper` переведен на pure-DI initializer без `InputSourceManaging` и optional production defaults;
- production composition перенесен в `AppDelegate.makeRetyper()`;
- production `Task.sleep(nanoseconds:)`, input-source operations, CGEvent posting и `CapsLockGuard()` теперь задаются на app boundary;
- `RetyperTests`, `TypingPipelineTests` и `HotkeyCoordinatorTests` получили явные deterministic closures и inert `CapsLockGuard`;
- добавлен safety-test `retyperDoesNotUseTaskSleepDirectly`;
- guard сканирует `LayoutSwitcher/Mapping/Retyper.swift` после удаления comments/strings и запрещает возврат `Task.sleep` внутрь `Retyper`.

**Ожидаемый эффект:** `Retyper` стал вычислительно-оркестрационным value type с полностью явными side-effect dependencies. Runtime-поведение сохраняется через `AppDelegate`, а тесты больше не получают скрытый access к реальным input sources, Caps Lock или wall-clock sleep.

**Статус:** verified. Targeted RetyperTests + TypingPipelineTests + HotkeyCoordinatorTests + AppDelegateTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 91 tests / 5 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 353 tests / 47 suites.

## Шаг 181. Explicit production factory для `CapsLockGuard`

**Наблюдение:** после шага 180 `Retyper` больше не создавал `CapsLockGuard` внутри себя, но сам `CapsLockGuard` все еще имел production defaults в initializer-е: `CGEventSource.flagsState(...)` и IOKit setter были доступны как скрытые default closures. Это оставляло маленькую лазейку: простой `CapsLockGuard()` снова мог бы подключить live system state без явного выбора production boundary.

**Изменения:**
- initializer `CapsLockGuard` теперь требует явные `readCapsLockState` и `setCapsLockState` closures;
- production composition перенесен в `CapsLockGuard.live()`;
- `AppDelegate.makeRetyper()` теперь передает `CapsLockGuard.live()` вместо `CapsLockGuard()`;
- добавлен safety-test `capsLockGuardRequiresExplicitSideEffectClosures`;
- guard проверяет, что live Caps Lock closures не возвращены как default arguments initializer-а.

**Ожидаемый эффект:** Caps Lock I/O остается доступным для runtime, но больше не включается неявно через пустой initializer. Тесты и будущие call sites должны явно выбирать deterministic closures или production factory, что лучше соответствует DI-дисциплине проекта.

**Статус:** verified. Targeted CapsLockGuardTests + RetyperTests + AppDelegateTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 63 tests / 4 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 354 tests / 47 suites.

## Шаг 182. Explicit clock boundary для `WordBuffer`

**Наблюдение:** `WordBuffer` хранит mutable typing buffer и формирует `CommittedWord.committedAt` при commit-е. До шага clock был injectable, но production `Date.init` оставался default argument в initializer-е. Это делало простой `WordBuffer()` скрытым обращением к wall-clock state, хотя runtime clock должен выбираться на composition boundary.

**Изменения:**
- initializer `WordBuffer` теперь требует явный `now` closure без `Date.init` default;
- production `Date.init` перенесен в `AppDelegate` при создании `wordBuffer`;
- `WordBufferTests` и прямые `TypingPipelineTests` получили deterministic fixed clock;
- добавлен safety-test `wordBufferRequiresExplicitClock`;
- guard проверяет, что `WordBuffer` не возвращает `Date.init` / `Date()` как default clock.

**Ожидаемый эффект:** timestamps committed words остаются runtime-функцией приложения, но unit tests и future call sites больше не получают скрытый wall-clock dependency через пустой initializer. Это продолжает линию явных time boundaries после `SequenceDetector` и `TypingPipeline`.

**Статус:** verified. Targeted WordBufferTests + TypingPipelineTests + AppDelegateTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 84 tests / 4 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 355 tests / 47 suites.

## Шаг 183. Pure DI boundary для `SmartPaste`

**Наблюдение:** `SmartPaste` уже был value type и имел test initializer с injected dependencies, но production initializer `init(inputSources:)` все еще подключал runtime side effects внутри самого helper-а: `NSPasteboard.general`, synthetic key posting и `Task.sleep(nanoseconds:)`. Это повторяло уже закрытый паттерн из `Retyper`: orchestration-компонент сам знал о production I/O.

**Изменения:**
- `SmartPaste` переведен на единственный explicit DI initializer с `pasteboardRead`, `postKeyEvent` и `sleep`;
- production composition перенесен в `AppDelegate.makeSmartPaste()`;
- synthetic key posting вынесен в явную `SmartPaste.postKey(keyCode:flags:)`, которую production boundary передает как closure;
- `NSPasteboard.general` и `Task.sleep(nanoseconds:)` больше не находятся внутри `SmartPaste` initializer-а;
- добавлен safety-test `smartPasteKeepsProductionDependenciesOnAppBoundary`;
- guard запрещает возврат `Task.sleep` и `NSPasteboard.general` внутрь `LayoutSwitcher/Mapping/SmartPaste.swift`.

**Ожидаемый эффект:** smart-paste остается runtime-функцией приложения, но сам helper больше не содержит скрытого clipboard/wall-clock wiring. Тесты и future call sites должны явно выбирать deterministic closures или production boundary, что укрепляет DI-дисциплину вокруг pasteboard и synthetic input.

**Статус:** verified. Targeted SmartPasteTests + AppDelegateTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 62 tests / 3 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 356 tests / 47 suites.

## Шаг 184. Pure DI boundary для `SelectionConverter`

**Наблюдение:** `SelectionConverter` уже был value type и имел explicit DI initializer для Accessibility, pasteboard, key posting и delay, но рядом оставался production initializer `init(mapping:focused:)`. Он напрямую подключал `AXUIElementCreateSystemWide`, `NSPasteboard.general`, synthetic `CGEvent` posting и `Task.sleep(nanoseconds:)`. При этом production call site для этого initializer-а сейчас отсутствует, то есть скрытая runtime-дверь была лишней и противоречила текущей DI-дисциплине.

**Изменения:**
- удален production initializer `SelectionConverter.init(mapping:focused:)`;
- `SelectionConverter` оставлен с единственным explicit DI initializer-ом;
- удалена ненужная зависимость `import AppKit` из файла converter-а;
- добавлен safety-test `selectionConverterKeepsProductionDependenciesInjected`;
- guard запрещает возврат `Task.sleep`, `NSPasteboard.general` и `AXUIElementCreateSystemWide` внутрь `LayoutSwitcher/Mapping/SelectionConverter.swift`.

**Ожидаемый эффект:** manual selection conversion остается полностью тестируемым orchestration helper-ом. Future production wiring должен быть добавлен явно на app boundary, а не спрятан в helper initializer-е, что снижает риск неявного доступа к Accessibility, clipboard и wall-clock scheduling.

**Статус:** verified. Targeted SelectionConverterTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 59 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 357 tests / 47 suites.

## Шаг 185. Explicit clock boundary для `HotkeyCoordinator`

**Наблюдение:** `HotkeyCoordinator` уже использует injectable `now` для undo/manual окон, но initializer всё еще оставлял production-default `Date.init`. Это удобно для вызова, но нарушает текущую DI-дисциплину проекта: время является side effect и должно явно передаваться на composition boundary, чтобы тесты не могли случайно вернуться к wall-clock behavior.

**Изменения:**
- у `HotkeyCoordinator.init(...)` удален default `now: Date.init`;
- `AppDelegate` теперь явно передает `now: Date.init` при создании production coordinator;
- тестовая fixture `HotkeyCoordinatorTests` сохраняет deterministic clock через `now: { currentDate }`;
- `SwiftSafetyRulesTests` получил guard `hotkeyCoordinatorRequiresExplicitClock`, запрещающий возврат `= Date.init` / `= Date()` в coordinator initializer.

**Ожидаемый эффект:** hotkey orchestration становится полностью явной по времени: runtime получает системные часы только на app boundary, а unit tests обязаны передавать controlled clock. Это снижает риск flaky behavior вокруг undo/manual windows и укрепляет правило “side effects only through injection”.

**Статус:** verified. Targeted HotkeyCoordinatorTests + AppDelegateTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 65 tests / 3 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 358 tests / 47 suites.

## Шаг 186. Explicit `UserDefaults` boundary для `OnboardingCompletionStore`

**Наблюдение:** `OnboardingCompletionStore` уже имел тестируемый initializer через `readCompleted` / `writeCompleted`, но convenience initializer скрывал production dependency через `UserDefaults = .standard`. Для first-run состояния это небольшой, но важный источник неявной глобальной зависимости: app boundary должен явно передавать persistent storage, а сам store должен оставаться deterministic и injection-friendly.

**Изменения:**
- у `OnboardingCompletionStore.init(defaults:)` удален default `.standard`;
- `AppDelegate` теперь явно создает `OnboardingCompletionStore(defaults: .standard)`;
- closure-based initializer для тестов сохранен без изменения поведения;
- `SwiftSafetyRulesTests` получил guard `onboardingCompletionStoreRequiresExplicitDefaults`, запрещающий возврат `UserDefaults = .standard` / `UserDefaults.standard` внутрь store.

**Ожидаемый эффект:** completion-state onboarding больше не несет скрытую production-зависимость. Тесты продолжают использовать deterministic closures, а runtime wiring остается в composition root.

**Статус:** verified. Targeted OnboardingCompletionStoreTests + AppDelegateTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 60 tests / 3 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 359 tests / 47 suites.

## Шаг 187. Explicit `UserDefaults` boundary для `HotkeyRegistry`

**Наблюдение:** `HotkeyRegistry` хранит пользовательские хоткеи и уже хорошо тестируется через isolated `UserDefaults` suites, но production initializer всё еще имел скрытый default `UserDefaults = .standard`. Для mutable UI-bound registry это оставляет неявную глобальную зависимость внутри сервиса, хотя реальное место выбора persistent storage должно быть в `AppDelegate`.

**Изменения:**
- у `HotkeyRegistry.init(defaults:)` удален default `.standard`;
- `AppDelegate` теперь явно создает `HotkeyRegistry(defaults: .standard)`;
- существующие `HotkeyRegistryTests` остались deterministic и продолжают передавать isolated defaults;
- `SwiftSafetyRulesTests` получил guard `hotkeyRegistryRequiresExplicitDefaults`, запрещающий возврат `UserDefaults = .standard` / `UserDefaults.standard` внутрь registry.

**Ожидаемый эффект:** хранение hotkey bindings теперь следует тому же правилу, что и onboarding completion: production storage выбирается на composition boundary, а сам registry остается явно сконфигурированным и тестируемым.

**Статус:** verified. Targeted HotkeyRegistryTests + AppDelegateTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 71 tests / 3 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 360 tests / 47 suites.

## Шаг 188. Explicit `UserDefaults` boundary для `RecentSwitches`

**Наблюдение:** `RecentSwitches` является `@Observable` history-store для последних исправлений и уже получает isolated defaults в unit tests, но production initializer всё еще скрывал `UserDefaults = .standard`. Для persisted state это тот же класс риска, что и у hotkey/onboarding storage: сервис выглядит полностью инъектируемым в тестах, но при обычном вызове может незаметно уйти в global defaults.

**Изменения:**
- у `RecentSwitches.init(defaults:)` удален default `.standard`;
- `AppDelegate` теперь явно создает `RecentSwitches(defaults: .standard)`;
- существующие `RecentSwitchesTests`, `HotkeyCoordinatorTests` и `TypingPipelineTests` сохраняют deterministic defaults через явную передачу suite;
- `SwiftSafetyRulesTests` получил guard `recentSwitchesRequiresExplicitDefaults`, запрещающий возврат `UserDefaults = .standard` / `UserDefaults.standard` внутрь recent history store.

**Ожидаемый эффект:** persisted history последних переключений теперь полностью следует DI-правилу проекта: storage выбирается на composition boundary, а сам сервис не содержит скрытой production-зависимости.

**Статус:** verified. Targeted RecentSwitchesTests + AppDelegateTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 67 tests / 3 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 361 tests / 47 suites.

## Шаг 189. Explicit `UserDefaults` boundary для `PerAppLayoutPreferences`

**Наблюдение:** `PerAppLayoutPreferences` хранит persisted mapping `bundleID → inputSourceID` и участвует в предотвращении ввода в неверной раскладке при смене приложения. Тесты уже передают isolated defaults, но production initializer всё еще имел скрытый default `UserDefaults = .standard`, что нарушает общий DI-подход для persisted state.

**Изменения:**
- у `PerAppLayoutPreferences.init(defaults:)` удален default `.standard`;
- `AppDelegate` теперь явно создает `PerAppLayoutPreferences(defaults: .standard)`;
- существующие `PerAppLayoutPreferencesTests` остались deterministic и продолжают передавать isolated defaults;
- `SwiftSafetyRulesTests` получил guard `perAppLayoutPreferencesRequiresExplicitDefaults`, запрещающий возврат `UserDefaults = .standard` / `UserDefaults.standard` внутрь per-app preferences store.

**Ожидаемый эффект:** persisted preferences по приложениям теперь создаются так же явно, как hotkeys, onboarding completion и recent switches. Storage выбирается на composition boundary, а сам store остается без скрытой production-зависимости.

**Статус:** verified. Targeted PerAppLayoutPreferencesTests + AppDelegateTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 69 tests / 3 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 362 tests / 47 suites.

## Шаг 190. Explicit defaults и clock boundary для `UsageStats`

**Наблюдение:** `UsageStats` хранит счетчики в `UserDefaults` и использует текущую дату для day rollover. До шага 190 initializer сам подставлял `.standard` и `Date.init`, из-за чего production dependencies были спрятаны внутри модели статистики.

**Изменения:**
- initializer `UsageStats` теперь требует явные `defaults` и `now`;
- `AppDelegate` стал единственной production-точкой, где передаются `.standard` и `Date.init`;
- тестовые потребители `TypingPipelineTests` и `HotkeyCoordinatorTests` получили детерминированный clock через `Date(timeIntervalSince1970: 0)`;
- `SwiftSafetyRulesTests` получил guard `usageStatsRequiresExplicitDefaultsAndClock`, запрещающий возврат скрытых `.standard` / `Date.init` defaults внутрь `UsageStats`.

**Ожидаемый эффект:** статистика остается UI-bound `@Observable` reference type, но ее side effects и clock теперь явно видны на composition boundary. Это снижает риск недетерминированных тестов и случайного чтения live `UserDefaults` вне `AppDelegate`.

**Статус:** verified. Targeted TypingPipelineTests + HotkeyCoordinatorTests + AppDelegateTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 94 tests / 4 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 363 tests / 47 suites.

## Шаг 191. Explicit defaults и clock boundary для `AppState`

**Наблюдение:** `AppState` является корректным `@Observable` reference type, потому что хранит UI-bound runtime/settings state. При этом initializer скрывал две production-зависимости: `UserDefaults.standard` и live clock `Date.init`. Это размывало границу между моделью состояния и composition root.

**Изменения:**
- initializer `AppState` теперь требует явные `defaults` и `now`;
- `AppDelegate` явно создает production `AppState(defaults: .standard, now: Date.init)`;
- `AppStateTests`, `TypingPipelineTests` и `HotkeyCoordinatorTests` передают детерминированный clock;
- `SwiftSafetyRulesTests` получил guard `appStateRequiresExplicitDefaultsAndClock`, запрещающий возврат скрытых production defaults внутрь `AppState`.

**Ожидаемый эффект:** `AppState` остается центральной main-actor моделью UI-состояния, но persistence и clock теперь видны при сборке зависимостей. Это улучшает тестируемость snooze/settings-сценариев и продолжает линию проекта: production dependencies живут на границе приложения, а не внутри сервисов/моделей.

**Статус:** verified. Targeted AppStateTests + TypingPipelineTests + HotkeyCoordinatorTests + AppDelegateTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 99 tests / 5 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 364 tests / 47 suites.

## Шаг 192. Explicit defaults и workspace boundary для `ExclusionList`

**Наблюдение:** `ExclusionList` уже имел injectable `localizedNameProvider`, но его convenience initializer скрывал две production-зависимости: `UserDefaults.standard` и `NSWorkspace.shared`. Из-за этого тестовый pipeline мог случайно получать live workspace lookup, хотя для логики исключений это не требуется.

**Изменения:**
- initializer `ExclusionList(defaults:workspace:)` теперь требует явные `defaults` и `workspace`;
- initializer `ExclusionList(defaults:localizedNameProvider:)` теперь также требует явные `defaults`;
- `AppDelegate` стал явной production-точкой для `.standard` и `.shared`;
- `TypingPipelineTests` использует deterministic `localizedNameProvider`, не обращаясь к live `NSWorkspace`;
- `SwiftSafetyRulesTests` получил guard `exclusionListRequiresExplicitDefaultsAndWorkspace`.

**Ожидаемый эффект:** список исключений сохраняет поведение первого запуска и migration logic, но production dependencies больше не спрятаны в default-параметрах initializer-ов. Это продолжает вынос side effects на composition boundary и делает pipeline-fixtures чище.

**Статус:** verified. Targeted ExclusionListTests + TypingPipelineTests + AppDelegateTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 94 tests / 4 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 365 tests / 47 suites.

## Шаг 193. Injected bundle-name lookup для recent/per-app UI

**Наблюдение:** после явного `ExclusionList(defaults:workspace:)` оставались прямые вызовы `ExclusionList.localizedName(for:)` в `HotkeyCoordinator`, `RetypeDispatcher` и `PerAppLayoutPreferences`. Эти вызовы не влияют на алгоритм переключения, но являются UI/diagnostic lookup side effect через `NSWorkspace`, спрятанным внутри runtime-сервисов.

**Изменения:**
- `HotkeyCoordinator` получил injected `bundleNameProvider` для manual/selection recent entries;
- `RetypeDispatcher` получил injected `bundleNameProvider` для automatic recent entries;
- `TypingPipeline` прокидывает `bundleNameProvider` в dispatcher;
- `PerAppLayoutPreferences` получил injected `appNameProvider` для сортировки настроек per-app layouts;
- `AppDelegate` стал единственной production-точкой, где эти provider-ы связываются с `ExclusionList.localizedName(for:workspace:)`;
- `SwiftSafetyRulesTests` получил guard `bundleNameLookupsStayInjectedOutsideAppBoundary`.

**Ожидаемый эффект:** lookup названий приложений теперь явно находится на composition boundary, а core runtime-сервисы работают с injected provider-ами. Это уменьшает неявные зависимости от `NSWorkspace`, упрощает тесты и сохраняет прежнее поведение UI/recent history в production.

**Статус:** verified. Targeted HotkeyCoordinatorTests + TypingPipelineTests + PerAppLayoutPreferencesTests + AppDelegateTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 106 tests / 5 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 366 tests / 47 suites.

## Шаг 194. Explicit `NSSpellChecker` boundary для `SystemSpellCheckerDictionary`

**Наблюдение:** `SystemSpellCheckerDictionary` уже был хорошо тестируемым через `SpellChecking`, но production singleton `NSSpellChecker.shared` оставался default argument внутри adapter initializer. Из-за этого любой новый вызов `SystemSpellCheckerDictionary(language:)` мог незаметно получить живой macOS spell checker, минуя явную DI-точку.

**Изменения:**
- initializer `SystemSpellCheckerDictionary` теперь требует explicit `checker: any SpellChecking`;
- factory `LayoutDetector.defaultMultilingual(...)` принимает `systemSpellChecker` явно и прокидывает его во все системные dictionary adapters;
- production wiring в `AppDelegate` передает `NSSpellChecker.shared` на границе приложения;
- `LayoutDetectorTests` используют deterministic `DeterministicSpellChecker`, не зависящий от системных словарей macOS;
- `SwiftSafetyRulesTests` получил guard `systemSpellCheckerStaysInjectedOutsideAppBoundary`, запрещающий вернуть `NSSpellChecker.shared` в adapter/factory internals.

**Ожидаемый эффект:** системный spell checker остается production dependency, но больше не прячется в default parameter. Тесты и фабрики становятся честнее: источник macOS API виден в call site, а detector defaults остаются композицией зависимостей, а не местом скрытого singleton-доступа.

**Статус:** verified. Первый targeted run выявил, что полностью rejecting fake ломает сценарий `romanianMultipleDiacriticVariantsAreKept`; fake заменен на deterministic checker, который явно знает только нужное test word `tara` для `ro`. Targeted SystemSpellCheckerTests + LayoutDetectorTests + AppDelegateTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 96 tests / 4 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 367 tests / 47 suites.

## Шаг 195. Explicit `NSWorkspace` boundary для `FocusedAppObserver`

**Наблюдение:** `FocusedAppObserver` уже имел injectable closures для frontmost app snapshot, activation observer и observer removal. Однако convenience initializer всё еще скрывал production dependency через `workspace: NSWorkspace = .shared`. Это не прямой `NSWorkspace.shared` access, но по смыслу такой же implicit production default: новый call site мог создать live observer без явного выбора workspace boundary.

**Изменения:**
- convenience initializer `FocusedAppObserver` теперь требует explicit `workspace: NSWorkspace`;
- `AppDelegate` стал единственным production call site и передает `.shared` явно;
- `SwiftSafetyRulesTests` получил guard `focusedAppObserverRequiresExplicitWorkspaceBoundary`, который запрещает возврат `NSWorkspace = .shared` в observer initializer;
- существующий testable initializer с injected closures сохранен без изменения поведения.

**Ожидаемый эффект:** workspace dependency стала видимой на границе приложения. `FocusedAppObserver` остается удобным production adapter, но больше не прячет live macOS workspace внутри default argument.

**Статус:** verified. Первый targeted compile выявил два legacy test fixtures в `TypingPipelineTests`, где использовался implicit `FocusedAppObserver()`; fixtures переведены на injected observer через deterministic closures. Targeted FocusedAppObserverTests + AppDelegateTests + TypingPipelineTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 96 tests / 4 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 368 tests / 47 suites.

## Шаг 196. Explicit `NSWorkspace` boundary для `PresentationModeDetector`

**Наблюдение:** `PresentationModeDetector` уже имел deterministic initializer через `frontmostBundleIDProvider`, но production initializer держал `workspace: NSWorkspace = .shared`. Это оставляло скрытый live macOS dependency внутри value-typed detector и позволяло создавать production-backed detector без явного указания workspace boundary.

**Изменения:**
- initializer `PresentationModeDetector(workspace:presentationBundleIDs:)` теперь требует explicit `workspace`;
- `AppDelegate` стал явным production call site и передает `.shared`;
- `SwiftSafetyRulesTests` получил guard `presentationModeDetectorRequiresExplicitWorkspaceBoundary`;
- существующие tests с `frontmostBundleIDProvider` не менялись и остаются deterministic.

**Ожидаемый эффект:** presentation-mode detection сохраняет прежнее поведение, но зависимость от `NSWorkspace` теперь видна в production wiring. Случайный возврат к implicit `.shared` будет пойман safety-suite.

**Статус:** verified. Targeted PresentationModeDetectorTests + AppDelegateTests + TypingPipelineTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 96 tests / 4 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 369 tests / 47 suites.

## Шаг 197. Explicit `NSWorkspace` boundary для `AccessibilityPermission`

**Наблюдение:** `AccessibilityPermission` уже имел injectable closures для trust state, prompt requester, settings opener и polling timer. Однако convenience initializer скрывал production dependency через `workspace: NSWorkspace = .shared`, поэтому новый call site мог создать live permission observer без явного указания macOS workspace boundary.

**Изменения:**
- convenience initializer `AccessibilityPermission(pollingInterval:workspace:)` теперь требует explicit `workspace`;
- `AppDelegate` стал явным production call site и передает `.shared`;
- `SwiftSafetyRulesTests` получил guard `accessibilityPermissionRequiresExplicitWorkspaceBoundary`;
- существующие tests с injected closures не менялись и остаются deterministic.

**Ожидаемый эффект:** Accessibility permission flow сохраняет прежнее поведение, но зависимость от `NSWorkspace` теперь видна в production wiring. Случайный возврат к implicit `.shared` будет пойман safety-suite.

**Статус:** verified. Targeted AccessibilityPermissionTests + AppDelegateTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 74 tests / 3 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 370 tests / 47 suites.

## Шаг 198. Explicit `FileManager` boundary для `UserDictionary`

**Наблюдение:** `UserDictionary` уже поддерживал injectable storage closures для deterministic tests, но production convenience initializer и helper `fileURL(...)` оставляли скрытый filesystem dependency через `FileManager = .default`. Это делало live storage boundary менее заметной и позволяло создать filesystem-backed dictionary без явного выбора `FileManager`.

**Изменения:**
- convenience initializer `UserDictionary(language:storageURL:fileManager:)` теперь требует explicit `fileManager`;
- helper `fileURL(for:fileManager:)` больше не имеет implicit `.default`;
- `AppDelegate` стал явным production call site и передает `.default` для четырех user dictionaries;
- `LayoutDetectorTests` больше не используют real `FileManager.default` для helper dictionaries и переходят на injected storage closures;
- `SwiftSafetyRulesTests` получил guard `userDictionaryRequiresExplicitFileManagerBoundary`.

**Ожидаемый эффект:** user dictionaries сохраняют прежнее production-поведение, но зависимость от файловой системы теперь видна в composition root. Тестовые dictionaries остаются fully deterministic и не трогают реальную файловую систему.

**Статус:** verified. Targeted UserDictionaryTests + LayoutDetectorTests + AppDelegateTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 97 tests / 4 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 371 tests / 47 suites.

## Шаг 199. Explicit defaults/clock/ID boundary для `LearningCache`

**Наблюдение:** `LearningCache` уже был value type и хранил dependencies как injected properties, но initializer всё еще имел production defaults: `UserDefaults = .standard`, `Date.init` и `UUID.init`. Поэтому cache можно было создать с live persistence/time/ID generation вне composition root.

**Изменения:**
- initializer `LearningCache(defaults:now:makeEntryID:)` теперь требует explicit `UserDefaults`, clock и ID factory;
- `AppDelegate` стал явным production call site и передает `.standard`, `Date.init`, `UUID.init`;
- `LearningCacheTests` получили deterministic helper `makeCache(...)` без live clock/random UUID defaults;
- `SwiftSafetyRulesTests` получил guard `learningCacheRequiresExplicitDefaultsClockAndIDFactory`.

**Ожидаемый эффект:** cache сохраняет прежнее production-поведение, но persistence/time/ID side effects теперь видны в composition root. Тесты остаются deterministic, а случайный возврат implicit production defaults будет пойман safety-suite.

**Статус:** verified. Targeted LearningCacheTests + AppDelegateTests + TypingPipelineTests + HotkeyCoordinatorTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 112 tests / 5 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 372 tests / 47 suites.

## Шаг 200. Explicit `PipelineTunables` boundary для pipeline/retype dispatch

**Наблюдение:** `TypingPipeline` и `RetypeDispatcher` уже получали большинство collaborators через initializer, но `PipelineTunables = .default` оставался implicit domain-policy default. У `RetypeDispatcher` дополнительно сохранялся implicit live clock через `Date.init`. Это делало cooldown/sequence policy и timestamp source менее заметными на границе pipeline wiring.

**Изменения:**
- `TypingPipeline` теперь требует explicit `tunables`;
- `RetypeDispatcher` теперь требует explicit `tunables` и `now`;
- production `AppDelegate` уже передавал `.default`, поэтому runtime wiring не изменился;
- `TypingPipelineTests` явно передают `.default` в локальных fixtures;
- `SwiftSafetyRulesTests` получил guard `pipelineTunablesStayExplicitAtPipelineBoundaries`.

**Ожидаемый эффект:** pipeline policy остается прежней, но ее больше нельзя неявно получить из initializer default. Clock для dispatch timestamps также остается явной dependency, что лучше соответствует Swift 6 testability/DI rules.

**Статус:** verified. Targeted TypingPipelineTests + HotkeyCoordinatorTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 103 tests / 3 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 373 tests / 47 suites.

## Шаг 201. Explicit `DetectionThresholds` boundary для `LayoutDetector`

**Наблюдение:** после подключения sensitivity через `decide(..., thresholds:)` сам detector все еще мог создаваться с implicit `DetectionThresholds = .default`. Это оставляло policy fallback скрытым внутри initializer/factory, хотя по правилам проекта domain policy должна быть видна на wiring boundary.

**Изменения:**
- `LayoutDetector.init(...)` теперь требует explicit `thresholds`;
- `LayoutDetector.defaultMultilingual(...)` теперь требует explicit `thresholds`;
- production `AppDelegate` явно передает `.default` при создании detector;
- detector/pipeline fixtures в тестах явно передают `.default`;
- `SwiftSafetyRulesTests` получил guard `layoutDetectorThresholdsStayExplicitAtConstructionBoundaries`.

**Ожидаемый эффект:** runtime-поведение остается прежним, но threshold policy больше нельзя получить неявно при construction. Это делает fallback-конфигурацию detector такой же явной, как pipeline tunables и clock dependencies в предыдущем шаге.

**Статус:** verified. Targeted LayoutDetectorTests + LayoutDetectorSmokeTests + LanguageScorerTests + TypingPipelineTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 136 tests / 5 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 374 tests / 47 suites.

## Шаг 202. Explicit NaturalLanguage scorer policy

**Наблюдение:** после явного `DetectionThresholds` на construction boundary у `LayoutDetector` оставался скрытый fallback ниже по цепочке: `NaturalLanguageScorer` сам брал `DetectionThresholds.default.naturalLanguageMinWordLength`, а `HybridLanguageScorer` мог неявно создать `NaturalLanguageScorer()`. Это делало часть sensitivity policy неявной внутри scoring layer.

**Изменения:**
- `NaturalLanguageScorer` теперь требует explicit `minimumTextLength` и `maximumHypotheses`;
- `HybridLanguageScorer` теперь требует explicit `naturalLanguageScorer`;
- `LayoutDetector.defaultMultilingual(...)` передает `minimumTextLength` из уже явного `thresholds.naturalLanguageMinWordLength`;
- `LanguageScorerTests` обновлены под explicit scorer configuration;
- `SwiftSafetyRulesTests` получил guard `naturalLanguageScorerPolicyStaysExplicit`.

**Ожидаемый эффект:** natural-language tie-break продолжает работать как раньше, но scorer больше не может незаметно вернуться к глобальному `DetectionThresholds.default`. Вся threshold policy идет сверху: production/test wiring -> detector factory -> hybrid scorer -> natural-language scorer.

**Статус:** verified. Targeted LanguageScorerTests + LayoutDetectorTests + LayoutDetectorSmokeTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 113 tests / 4 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 375 tests / 47 suites.

## Шаг 203. Explicit clock boundary для `ManualActionsCoordinator`

**Наблюдение:** `TypingPipeline` уже получает injected `now` и передает его в manual-action flow, но сам `ManualActionsCoordinator` все еще имел fallback `now: Date.init` в initializer. Для manual hotkey actions это скрытая wall-clock dependency: sentence conversion использует время для ограничения возраста committed words.

**Изменения:**
- `ManualActionsCoordinator.init(...)` теперь требует explicit `now`;
- `TypingPipeline` продолжает передавать свой injected clock без изменения runtime-поведения;
- `SwiftSafetyRulesTests` получил guard `manualActionsCoordinatorRequiresExplicitClock`.

**Ожидаемый эффект:** manual retype / convert-last-sentence flows используют тот же clock boundary, что и pipeline. Возврат к implicit wall-clock fallback будет пойман safety-suite.

**Статус:** verified. Targeted TypingPipelineTests + HotkeyCoordinatorTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 106 tests / 3 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 376 tests / 47 suites.

## Шаг 204. Explicit notification-center boundary для `NotificationManager`

**Наблюдение:** `NotificationManager` уже поддерживал полностью injectable closure-based initializer, но convenience initializer все еще имел implicit production fallback `UNUserNotificationCenter = .current()`. Это оставляло системный notification center скрытой dependency внутри service boundary вместо явного wiring на уровне app composition.

**Изменения:**
- `NotificationManager(notificationCenter:makeNotificationID:)` теперь требует explicit `notificationCenter`;
- production `AppDelegate` явно передает `.current()`;
- closure-based initializer для тестов не изменился;
- `SwiftSafetyRulesTests` усилил guard `notificationManagerDoesNotAccessCurrentNotificationCenterDirectly`.

**Ожидаемый эффект:** runtime-поведение уведомлений не меняется, но системный `UNUserNotificationCenter` теперь подключается только на production boundary. Возврат implicit `.current()` в `NotificationManager` будет пойман safety-suite.

**Статус:** verified. Targeted NotificationManagerTests + AppDelegateTests + SwiftSafetyRulesTests: first run caught missing `UserNotifications` import; re-run `** TEST SUCCEEDED **`, 80 tests / 3 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 376 tests / 47 suites.

## Шаг 205. Explicit notification id factory для `NotificationManager`

**Наблюдение:** после вынесения `UNUserNotificationCenter.current()` на production boundary в `NotificationManager` оставался второй скрытый runtime default: `makeNotificationID` мог неявно использовать `UUID().uuidString`. Для уведомлений это корректное production-поведение, но сама случайность является side effect и должна быть явно подключена на уровне app composition.

**Изменения:**
- `NotificationManager(notificationCenter:makeNotificationID:)` теперь требует explicit `makeNotificationID`;
- production `AppDelegate` явно передает `{ UUID().uuidString }`;
- deterministic closure-based tests не меняют поведение;
- `SwiftSafetyRulesTests` усилил guard против возврата implicit UUID fallback в `NotificationManager`.

**Ожидаемый эффект:** runtime-уведомления продолжают получать уникальные id, но source of randomness больше не спрятан внутри service initializer. Тестовая детерминированность и DI-boundary стали жестче.

**Статус:** verified. Targeted NotificationManagerTests + AppDelegateTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 80 tests / 3 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 376 tests / 47 suites.

## Шаг 206. Explicit notification sound policy для `NotificationManager`

**Наблюдение:** после явного `notificationCenter` и `makeNotificationID` в `NotificationManager` оставался еще один скрытый production default: `content.sound = .default`. Это не ломало тесты, но смешивало assembly policy с логикой подготовки уведомления.

**Изменения:**
- `NotificationManager` получил explicit `notificationSound`;
- production `AppDelegate` явно передает `.default`;
- создание `UNMutableNotificationContent` использует injected sound policy;
- `SwiftSafetyRulesTests` запрещает возврат прямого `content.sound = .default` внутри `NotificationManager`.

**Ожидаемый эффект:** поведение для пользователя не меняется: уведомления по-прежнему имеют системный звук. При этом UI/OS policy теперь находится на production boundary, а сервис остается детерминированнее и прозрачнее для тестов.

**Статус:** verified. Targeted NotificationManagerTests + AppDelegateTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 80 tests / 3 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 376 tests / 47 suites.

## Шаг 207. Fail-fast isolated `UserDefaults` в тестах

**Наблюдение:** несколько тестовых fixtures создавали isolated `UserDefaults(suiteName:)`, но при `nil` fallback уходил в `UserDefaults.standard`. Это редкий, но неприятный риск: при проблеме с suite creation тесты могли незаметно писать в реальные пользовательские defaults и давать загрязненное состояние между прогонами.

**Изменения:**
- `ExclusionListTests`, `PerAppLayoutPreferencesTests`, `HotkeyRegistryTests`, `HotkeyCoordinatorTests` и `TypingPipelineTests` теперь используют `try #require(UserDefaults(suiteName: ...))`;
- тесты и fixtures, которым нужны isolated defaults, переведены на `throws`;
- fallback на `.standard` / `UserDefaults.standard` удален из этих suites;
- `SwiftSafetyRulesTests` получил guard `unitTestsDoNotFallbackToStandardUserDefaultsForIsolatedSuites`.

**Ожидаемый эффект:** если isolated defaults suite не создается, тест падает явно и рано. Тесты больше не могут тихо использовать реальные app/user defaults, а safety-suite удерживает это правило.

**Статус:** verified. Targeted ExclusionListTests + PerAppLayoutPreferencesTests + HotkeyRegistryTests + HotkeyCoordinatorTests + TypingPipelineTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 136 tests / 6 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 377 tests / 47 suites.

## Шаг 208. Fail-fast isolated `UserDefaults` для `RecentSwitchesTests`

**Наблюдение:** после шага 207 один test suite все еще сохранял fallback `UserDefaults(suiteName:) ?? .standard`: `RecentSwitchesTests`. Это оставляло тот же риск, что и в предыдущем шаге: при проблеме с созданием isolated suite тест мог незаметно использовать реальные defaults.

**Изменения:**
- `RecentSwitchesTests.makeDefaults(...)` теперь использует `try #require(UserDefaults(suiteName: ...))`;
- тесты `RecentSwitchesTests`, которым нужен isolated storage, переведены на `throws`;
- fallback на `.standard` удален из suite;
- guard `unitTestsDoNotFallbackToStandardUserDefaultsForIsolatedSuites` теперь покрывает `RecentSwitchesTests.swift`.

**Ожидаемый эффект:** тесты истории переключений больше не могут тихо писать в реальные defaults пользователя. Если isolated suite не создается, failure будет явным и локализованным.

**Статус:** verified. Targeted RecentSwitchesTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 82 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 377 tests / 47 suites.

## Шаг 209. Fail-fast isolated `UserDefaults` для `LearningCacheTests` и `AppStateTests`

**Наблюдение:** после закрытия fallback на `.standard` остались тестовые fixtures, где `UserDefaults(suiteName:)` обрабатывался через `Issue.record(...)` и ранний `return`. Такой тест не использовал реальные defaults, но мог завершиться как пропущенная логика вместо явного failure при проблеме с isolated suite.

**Изменения:**
- `LearningCacheTests.makeDefaults(...)` теперь возвращает `throws -> UserDefaults` и использует `try #require(UserDefaults(suiteName: ...))`;
- тесты `LearningCacheTests`, которым нужен isolated storage, переведены на `throws`;
- `AppStateTests.makeDefaults(...)` переведен на тот же fail-fast pattern;
- persistence-тесты `AppStateTests` переиспользуют общий helper вместо ручного `guard let UserDefaults(suiteName:)`.

**Ожидаемый эффект:** тесты learning cache и app state больше не могут тихо выйти из сценария при проблеме с isolated defaults. Ошибка создания suite станет явной, ранней и одинаковой с остальными тестами проекта.

**Статус:** verified. Targeted LearningCacheTests + AppStateTests: `** TEST SUCCEEDED **`, 13 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 377 tests / 47 suites.

## Шаг 210. Safety guard для fail-fast isolated `UserDefaults` в тестах

**Наблюдение:** шаги 207-209 привели test fixtures с isolated `UserDefaults(suiteName:)` к единому fail-fast pattern через `try #require(...)`. Но safety-suite пока защищал только fallback на `.standard` и не запрещал более мягкий вариант `Issue.record(...)` + ранний `return`.

**Изменения:**
- guard `unitTestsDoNotFallbackToStandardUserDefaultsForIsolatedSuites` расширен на `AppStateTests.swift` и `LearningCacheTests.swift`;
- добавлен guard `unitTestsFailFastWhenIsolatedUserDefaultsSuitesCannotBeCreated`;
- scanner проверяет test suites с `UserDefaults(suiteName:)` и запрещает возврат к `Issue.record(...)` / `guard let` для создания isolated defaults;
- правило продолжает игнорировать comments/strings через существующий sanitizer.

**Ожидаемый эффект:** будущие тесты больше не смогут тихо пропускать сценарий при проблеме с isolated defaults. Для всех suites с `UserDefaults(suiteName:)` закреплен единый стиль: `try #require(...)` и явный test failure.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 75 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 378 tests / 47 suites.

## Шаг 211. Injected file enumeration для `LocalizationCatalogTests`

**Наблюдение:** после серии DI-правок в runtime-коде и test defaults остался test-only singleton usage: `LocalizationCatalogTests` напрямую использовал `FileManager.default.enumerator(...)` для поиска Swift-файлов приложения. Это не влияло на runtime, но выбивалось из общего правила проекта: side effects должны быть явными dependency boundaries.

**Изменения:**
- `LocalizationCatalogTests.swiftFiles(...)` теперь принимает injected `FileEnumerator` closure;
- production-style test path передает `Self.enumerateFiles`, где создается локальный `FileManager()` instance без обращения к singleton `FileManager.default`;
- логика проверки localization keys не изменилась;
- `SwiftSafetyRulesTests` получил guard `localizationCatalogTestsKeepFileEnumerationInjected`, запрещающий возврат `FileManager.default` в `LocalizationCatalogTests.swift`.

**Ожидаемый эффект:** localization tests сохраняют прежнее покрытие, но file-system side effect становится явной test dependency. Будущий возврат к прямому singleton access будет пойман safety-suite.

**Статус:** verified. Targeted LocalizationCatalogTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 80 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 379 tests / 47 suites.

## Шаг 212. Injected file enumeration для `SwiftSafetyRulesTests`

**Наблюдение:** после шага 211 прямое использование `FileManager.default.enumerator(...)` осталось уже не в application tests, а в самом `SwiftSafetyRulesTests`. Это не влияло на runtime, но safety-suite является главным хранителем правил проекта, поэтому ему особенно важно не нарушать собственный DI-style.

**Изменения:**
- `SwiftSafetyRulesTests.swiftFiles(in:)` теперь делегирует работу overload-у с injected `FileEnumerator`;
- production-style test path использует `Self.enumerateFiles`, где создается локальный `FileManager()` instance без обращения к singleton `FileManager.default`;
- существующие call sites `swiftFiles(in:)` сохранены без изменения;
- добавлен self-guard `swiftSafetyRulesTestsKeepFileEnumerationInjected`, который проверяет sanitized source самого safety-suite.

**Ожидаемый эффект:** project scanner остается функционально тем же, но filesystem enumeration в safety-suite оформлена как явная dependency boundary. Будущий возврат к `FileManager.default` в исполняемом коде `SwiftSafetyRulesTests` будет пойман самим safety-suite.

**Статус:** verified. Targeted SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 77 tests / 1 suite. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 380 tests / 47 suites.

## Шаг 213. Deterministic suite names для isolated `UserDefaults` в тестах

**Наблюдение:** после fail-fast `UserDefaults` cleanup остались isolated defaults suites, где имя suite строилось через `UUID().uuidString`. Это не влияло на пользователя, но добавляло лишнюю случайность в unit tests. Общий random scanner не видел этот случай, потому что `UUID().uuidString` находился внутри string interpolation и удалялся sanitizer-ом вместе со string literal.

**Изменения:**
- `ExclusionListTests.makeDefaults(...)` и `PerAppLayoutPreferencesTests.makeDefaults(...)` перешли на deterministic suite name через `#function`;
- `HotkeyCoordinatorTests.makeFixture(...)` получает deterministic `testName: String = #function` и очищает persistent domain перед использованием;
- `TypingPipelineTests` получил общий helper `makeDefaults(_:)` и больше не создает suite names через `UUID().uuidString`;
- `SwiftSafetyRulesTests.unitTestsDoNotUseRandomAPIs` теперь дополнительно проверяет raw source на `UserDefaults(suiteName:)` + `UUID().uuidString`, чтобы interpolation-сценарий не обходил sanitizer.

**Ожидаемый эффект:** isolated defaults остаются разнесенными по тестам, но больше не зависят от random identifiers. Поведение тестов становится более воспроизводимым, а safety-suite ловит возврат случайных suite names.

**Статус:** verified. Targeted ExclusionListTests + PerAppLayoutPreferencesTests + HotkeyCoordinatorTests + TypingPipelineTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 126 tests / 5 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 380 tests / 47 suites.

## Шаг 214. Explicit ID factory для `RecentSwitchEntry`

**Наблюдение:** `RecentSwitchEntry` оставался доменной value-моделью с hidden side effect: initializer по умолчанию генерировал `id: UUID = UUID()`. Это удобно для call sites, но противоречит текущей DI-дисциплине проекта: random identifiers должны подключаться явно на composition boundary, а тесты должны использовать deterministic values.

**Изменения:**
- `RecentSwitchEntry` больше не имеет default `UUID()` в initializer-е;
- `RecentSwitches` получил injected `makeEntryID: @MainActor () -> UUID`;
- runtime `AppDelegate` явно передает `UUID.init` при создании `RecentSwitches`;
- `HotkeyCoordinator` и `RetypeDispatcher` теперь записывают recent entries через `RecentSwitches.record(...)`, где ID создается injected factory;
- тесты `RecentSwitchesTests`, `HistoryTabTests`, `TypingPipelineTests` и `HotkeyCoordinatorTests` используют deterministic fixed UUID helper;
- `SwiftSafetyRulesTests` получил guard `recentSwitchesRequiresExplicitEntryIDFactory`, запрещающий возврат `UUID()` внутрь `RecentSwitches.swift`.

**Ожидаемый эффект:** recent-history сохраняет прежнее runtime-поведение, но генерация ID стала явной зависимостью. Тесты больше не зависят от случайных UUID, а будущий откат к hidden random default будет пойман safety-suite.

**Статус:** verified. Targeted RecentSwitchesTests + HistoryTabTests + TypingPipelineTests + HotkeyCoordinatorTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 121 tests / 5 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 381 tests / 47 suites.

## Шаг 215. Declarative assertions в `SmartPasteTests`

**Наблюдение:** часть `SmartPasteTests` проверяла успешный `.pasted` результат через ручной `if case ... else { Issue.record(...) }`. Это рабочий Swift Testing паттерн, но в данном файле результат уже можно выразить декларативно через `#expect`: отдельно проверить, что case действительно `.pasted`, и отдельно проверить распознанный `LanguageID`.

**Изменения:**
- сценарии русского, английского, украинского и румынского clipboard больше не используют `Issue.record(...)`;
- вместо ручного failure branch тесты выставляют локальные `isPasted` / `pastedLanguage` и проверяют их через `#expect`;
- `SwiftSafetyRulesTests` получил guard `smartPasteTestsUseExpectInsteadOfIssueRecord`, запрещающий возврат `Issue.record` в `SmartPasteTests.swift`.

**Ожидаемый эффект:** `SmartPasteTests` становятся ближе к единому стилю Swift Testing в проекте: основной verdict выражен через `#expect`, а не через ручную запись issue. Поведение тестируемого `SmartPaste` не меняется.

**Статус:** verified. Targeted SmartPasteTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 87 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 382 tests / 47 suites.

## Шаг 216. Declarative assertions в `SelectionConverterTests`

**Наблюдение:** `SelectionConverterTests` все еще использовал ручные `Issue.record(...)` ветки для expected `.success` / `.failure` cases. Это не ломало suite, но делало проверки менее единообразными: часть verdict-а была выражена не через `#expect`, а через imperative failure path с ранним `return`.

**Изменения:**
- success-сценарии clipboard fallback теперь выставляют `isSuccess` и `isClipboardMethod`, затем проверяют их через `#expect`;
- failure-сценарии `.noSelection`, `.tooLong` и `.conversionFailed` проверяются через boolean verdict + `#expect`;
- `SwiftSafetyRulesTests` получил guard `selectionConverterTestsUseExpectInsteadOfIssueRecord`, запрещающий возврат `Issue.record` в `SelectionConverterTests.swift`.

**Ожидаемый эффект:** тесты selection conversion становятся ближе к единому Swift Testing стилю проекта. Поведение `SelectionConverter` не меняется, но future regressions в expected result shape будут выражаться через стандартные assertions.

**Статус:** verified. Targeted SelectionConverterTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 85 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 383 tests / 47 suites.

## Шаг 217. Fail-fast section lookup в `HelpContentTests`

**Наблюдение:** `HelpContentTests` проверял наличие privacy section через `guard` + `Issue.record(...)` + early return. Для Swift Testing это менее точная форма, чем `try #require(...)`: missing fixture должен сразу помечать prerequisite failure и не продолжать dependent assertions.

**Изменения:**
- `privacySectionContainsKeyPhrases` теперь объявлен как `throws`;
- поиск privacy section переведен на `try #require(...)`;
- `SwiftSafetyRulesTests` получил guard `helpContentTestsUseRequireInsteadOfIssueRecord`, запрещающий возврат `Issue.record` в `HelpContentTests.swift`.

**Ожидаемый эффект:** тест явно отделяет prerequisite от содержательных `#expect` проверок текста. Если секция пропадет, failure станет короче и понятнее, без ручного imperative branch.

**Статус:** verified. Targeted HelpContentTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 85 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 384 tests / 47 suites.

## Шаг 218. Fail-fast rank lookup в `LanguageScorerTests`

**Наблюдение:** `LanguageScorerTests` проверял наличие entries в `LayoutDetector.tieBreakRank` через `guard` + `Issue.record(...)` + early return. Это снова prerequisite-проверка, для которой Swift Testing дает более точный инструмент `try #require(...)`.

**Изменения:**
- `tieBreakRankPrefersCyrillicThenRomanianThenEnglish` теперь объявлен как `throws`;
- lookup значений `.ru`, `.uk`, `.ro`, `.en` переведен на отдельные `try #require(...)`;
- `SwiftSafetyRulesTests` получил guard `languageScorerTestsUseRequireInsteadOfIssueRecord`, запрещающий возврат `Issue.record` в `LanguageScorerTests.swift`.

**Ожидаемый эффект:** если таблица tie-break priority случайно потеряет язык, тест упадет как явный missing prerequisite, а не через ручную issue-запись и ранний выход. Основные ordering assertions остаются прежними.

**Статус:** verified. Targeted LanguageScorerTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 90 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 385 tests / 47 suites.

## Шаг 219. Fail-fast localization key lookup в `LocalizationCatalogTests`

**Наблюдение:** `LocalizationCatalogTests` проверял наличие hotkey localization keys через `guard` + `Issue.record(...)` + `continue`. Для обязательных ключей это менее строгая форма: если ключ отсутствует, тест должен сразу зафиксировать missing prerequisite, а не продолжать цикл с частичным verdict.

**Изменения:**
- lookup hotkey localization entries переведен на `try #require(catalog.strings[key])`;
- ручной `Issue.record(...)` и `continue` удалены из `hotkeyActionKeysAreTranslatedForSupportedLanguages`;
- `SwiftSafetyRulesTests` получил guard `localizationCatalogTestsUseRequireInsteadOfIssueRecord`, запрещающий возврат `Issue.record` в `LocalizationCatalogTests.swift`.

**Ожидаемый эффект:** отсутствие обязательного localization key теперь падает как явная prerequisite-ошибка Swift Testing. Проверки переводов для найденного entry остаются прежними: `translated`, non-empty value и value не равен raw key.

**Статус:** verified. Targeted LocalizationCatalogTests + SwiftSafetyRulesTests: `** TEST SUCCEEDED **`, 87 tests / 2 suites. Build: `** BUILD SUCCEEDED **`. Full suite: `** TEST SUCCEEDED **`, 386 tests / 47 suites.
