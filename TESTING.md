# LayoutSwitcher — Manual Smoke Tests

Прогонять перед каждым релизом. Должен пройти на macOS 15.7+ с включёнными раскладками EN, RU, UK, RO.

---

## 0. Prerequisites

- [ ] **Accessibility:** System Settings → Privacy & Security → Accessibility → LayoutSwitcher включён.
- [ ] **Input Sources:** в System Settings → Keyboard → Input Sources добавлены минимум: U.S. + один из (Russian / Ukrainian / Romanian — Standard).
- [ ] **App запущен:** menu-bar иконка видна, badge соответствует активной раскладке (`EN`/`RU`/`UK`/`RO`).
- [ ] **Hotkeys зарегистрированы:** `⌃⌥\` (manual switch) и `⌃⌥c` (selection convert) — проверить в Settings → Hotkeys.

---

## 1. Golden flow (RU↔EN, обязательно)

В **TextEdit** (новый документ, layout EN активен):

| # | Действие | Ожидание |
|---|---|---|
| 1 | Набрать `ghbdtn<space>` | Слово заменяется на `привет<space>`, menu-bar badge → `RU`, иконка флипается |
| 2 | Сменить layout на RU вручную, набрать `руддщ<space>` | Заменяется на `hello<space>`, badge → `EN` |
| 3 | Сразу же снова `ghbdtn<space>` | Заменяется на `привет<space>` (повтор не подавляется когда смежные слова разные) |
| 4 | Набрать `привет<space>` (на RU) | **Не** заменяется (cooldown 1.5 сек после auto-switch) |
| 5 | Подождать 2 сек, набрать `привет<space>` снова | Остаётся как есть (real RU word — keep) |

---

## 2. Multi-word burst

| # | Действие | Ожидание |
|---|---|---|
| 1 | На EN: `ghbdtn rfr ltkf<space>` (3 слова) | Все 3 слова заменяются одним блоком на `привет как дела<space>`, layout → RU |
| 2 | На EN: `ghbdtn rfr.<space>` (2 слова + точка) | `привет как.<space>`, точка сохраняется, layout → RU |
| 3 | Многословный блок, потом focus в другое окно | Если pending sequence есть — buffer сбрасывается, retype не происходит |

---

## 3. Romanian (RO)

В TextEdit, layout RO активен, **в Settings → Languages → Auto-add Romanian diacritics включено**:

| # | Действие | Ожидание |
|---|---|---|
| 1 | Набрать `buna<space>` | Заменяется на `bună<space>` (диакритика добавляется) |
| 2 | Набрать `tara<space>` | **НЕ** заменяется (`tara` имеет 2+ диакритик-варианта `țara`/`tară`/`țară` — keep) |
| 3 | Набрать `Buna<space>` | Заменяется на `Bună<space>` (casing сохраняется) |

С **выключенной** настройкой → `buna` остаётся как есть.

---

## 4. Ukrainian (UK)

В TextEdit, layout EN:

| # | Действие | Ожидание |
|---|---|---|
| 1 | Набрать `ghbdsn<space>` (UK keymap для "привіт") | Заменяется на `привіт<space>`, layout → UK |

---

## 5. Per-app smoke

Прогнать в каждом приложении: набрать `ghbdtn<space>` на EN, ожидать `привет<space>`. Особые случаи отмечены ниже.

| App | Ожидание | Особенности |
|---|---|---|
| **TextEdit** | ✅ Replace | Baseline. |
| **Notes** | ✅ Replace | iCloud sync — иногда задержка отображения, но retype отрабатывает. |
| **Safari** (любая form) | ✅ Replace | Адресная строка тоже работает. |
| **Chrome** | ✅ Replace | Включая URL bar. |
| **VS Code** | ✅ Replace | Любой текстовый редактор. Cursor IDE / Windsurf — аналогично. |
| **Xcode** | ✅ Replace | Source editor; в Find Navigator тоже. |
| **Terminal** (default macOS) | ❌ **Не replace** (исключение по умолчанию) | bundle ID `com.apple.Terminal` в default exclusions. |
| **iTerm2** | ❌ **Не replace** | `com.googlecode.iterm2` в default exclusions. |
| **Slack** | ✅ Replace | Только в текстовых полях; команды (`/`-prefix) не трогаются если digit-poison сработал. |
| **Telegram (Desktop)** | ✅ Replace | |
| **Mail** | ✅ Replace | Subject + body. |
| **Microsoft Word** | ✅ Replace | |
| **1Password** (поле Login/Notes) | ❌ **Не replace** в `AXSecureTextField` | В обычном поле Notes — Replace; в Password — нет. |
| **Safari → password field** (login на любом сайте) | ❌ Не replace | secure field detection. |
| **Login window / sudo prompt** | ❌ Не replace | global `IsSecureEventInputEnabled()` = true → menu-bar badge `SC`, иконка `lock.fill`. |

**Расширенный список:** Discord, Figma, Linear, Obsidian, Notion, Tweetbot, Sketch, Photoshop — все должны вести себя как general text editors.

---

## 6. Edge cases / hotkeys

| # | Сценарий | Ожидание |
|---|---|---|
| 1 | `⌃⌥\` после набора `ghbdtn<space>` (EN) | Manual switch — слово заменяется даже если auto-pipeline не сработал |
| 2 | После auto-switch — `⌃⌥z` (undo) в течение 3 сек | Слово возвращается к оригиналу |
| 3 | После auto-switch — нотификация → нажать "Undo" | То же самое |
| 4 | Snooze (Settings → General → Snooze) | Auto-switch блокируется на N мин, badge `Pn` (где n = remaining minutes) |
| 5 | Open Keynote → start presentation | Badge `PR`, auto-switch suppressed |
| 6 | `Cmd+V` paste в любое поле | Buffer hard-reset, никаких retype в следующих словах |
| 7 | Ввод цифр (`abc123<space>`) | Token "poisoned" — replacement не срабатывает |
| 8 | IME активен (китайская/корейская/японская раскладка) | Никаких retype, buffer сбрасывается |
| 9 | Caps Lock включён, набрать `GHBDTN<space>` | Заменяется на `ПРИВЕТ<space>`, Caps Lock сохраняется (capture/restore через IOKit) |
| 10 | `⌃⌥c` после выделения wrong-layout текста | Selection conversion — выделенное заменяется без текстового ввода |

---

## 7. Settings UI

- [ ] **General** — toggle Enable, Snooze, Sound, Visual feedback, Romanian diacritics.
- [ ] **Layouts** — список доступных раскладок отображается, primary language бейджи корректны.
- [ ] **Hotkeys** — каждый из биндингов ловится `KeyRecorderView`, изменения регистрируются в Carbon manager.
- [ ] **Exclusions** — добавить bundle ID, проверить что в этом app retype блокируется.
- [ ] **Dictionaries** — добавить кастомное слово в EN dict, проверить что оно учитывается detector'ом (например — добавить "kek", набрать `сук<space>` (EN keymap) → не заменяется).
- [ ] **Learning** — после нескольких undo на одинаковом слове, оно перестаёт auto-switch'ить.
- [ ] **About** — версия отображается, "Export Logs" — кнопка работает, выгружает `os.Logger` поток.

---

## 8. Status item / menu bar

- [ ] Иконка отображает текущий язык overlay (EN/RU/UK/RO) поверх SF Symbol.
- [ ] При выключенном app — иконка `keyboard.chevron.compact.down`.
- [ ] При secure input (password field или global secure mode) — `lock.fill` + badge `SC`.
- [ ] При presentation mode — badge `PR`.
- [ ] При snooze — badge `Pn` (минуты).
- [ ] Recent switches submenu — последние 10 замен; "Add to exceptions" inline-action работает.

---

## 9. Onboarding

Удалить `~/Library/Preferences/GM.LayoutSwitcher.plist` (или сбросить `onboarding.completed` в UserDefaults), перезапустить:

- [ ] Запускается onboarding window (Welcome → Accessibility → Layouts → Hotkeys → Sandbox → Done).
- [ ] AX permission polling — после grant'а в System Settings шаг переключается автоматически.
- [ ] После Done — основной flow работает, повторно onboarding не появляется.

---

## 10. Logs sanity

- В `Console.app` фильтр `subsystem:GIH.LayoutSwitcher` — должны быть видны категории: `Pipeline`, `Detector`, `EventTap`, `Retyper`, `Help`, `Dictionary`.
- Никаких `error:` или `fault:` в нормальном flow.
- "Permission denied" / "AX not trusted" появляется только если permission реально не выдан.

---

## Reporting failures

При сбое прикладывать:

1. macOS version (`sw_vers -productVersion`).
2. Output `defaults read GM.LayoutSwitcher` (settings snapshot).
3. Зипованный лог из Settings → About → Export Logs.
4. Точную последовательность keystrokes + expected vs actual.
