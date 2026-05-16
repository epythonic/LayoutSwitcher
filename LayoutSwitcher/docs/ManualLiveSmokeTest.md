# Ручной live smoke-test перед tester release

Цель: перед публикацией тестерам подтвердить не только unit/UI-тесты, но и реальное поведение event tap, переключения input source, retype, звука и status item в живой macOS-сессии.

## Когда выполнять

- После `xcodebuild test -scheme LayoutSwitcher -destination 'platform=macOS'`.
- После `xcodebuild build -scheme LayoutSwitcher -destination 'platform=macOS'`.
- Перед сборкой DMG или публикацией GitHub Release для тестеров.
- После любых изменений в `TypingPipeline`, `LayoutDetector`, `Retyper`, feedback, hotkeys, input sources или настройках коррекции.

## Подготовка

1. Запустить свежую сборку `LayoutSwitcher.app`.
2. Проверить, что macOS выдала приложению Accessibility и Input Monitoring permissions.
3. В Settings включить:
   - автоматическое переключение;
   - исправление случайных удвоений;
   - Cupertino / common typo correction;
   - исправление двух заглавных подряд;
   - Ёфикатор;
   - sound feedback;
   - visual feedback.
4. Открыть TextEdit и создать новый plain text документ.
5. Повторить тот же набор в Notes, если перед релизом менялись focus/event-tap части.

## Сценарии TextEdit

| Сценарий | Ввод физической клавиатурой | Ожидаемый результат |
| --- | --- | --- |
| Wrong layout EN→RU | `ghbdtn ` на English layout | `привет `, раскладка переключилась на RU, feedback `.layoutSwitch` |
| Wrong layout RU→EN | `руддщ ` на Russian layout | `hello `, раскладка переключилась на EN, feedback `.layoutSwitch` |
| Duplicate letter | `helloo ` на English layout | `hello `, feedback `.duplicateLetter` |
| Legitimate duplicate | `account ` на English layout | слово не меняется |
| Legitimate Russian duplicate | `ванна ` на Russian layout | слово не меняется |
| Double capital | `ПРивет ` на Russian layout | `Привет `, feedback `.doubleCapital` |
| Ёфикатор | `ежик ` на Russian layout | `ёжик `, feedback `.russianYo` |
| Cupertino typo | `bokk ` или `hellp ` на English layout | `book ` / `hello `, feedback `.cupertino` |

## Что фиксировать

- Дата и build source: branch/commit или local build marker.
- Приложение для проверки: TextEdit, Notes.
- Какие сценарии пройдены и какие нет.
- Были ли отдельные звуки и визуальные бейджи для разных correction kind.
- Не было ли ложных срабатываний на `account`, `ванна`, `класс`, `сумма`.

## Release gate

Tester release можно собирать только если:

- `** TEST SUCCEEDED **`;
- `** BUILD SUCCEEDED **`;
- ручной TextEdit smoke-test пройден;
- при изменениях focus/event-tap поведения дополнительно пройден Notes smoke-test.
