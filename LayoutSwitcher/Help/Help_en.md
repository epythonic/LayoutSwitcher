## overview

LayoutSwitcher watches global keyboard input and corrects layout mistakes when it can do so safely.

Example:
• You type "ghbdtn " while the English layout is active.
• After the space, the app recognizes that the word reads as Russian.
• It replaces the just-typed word with "привет " and switches to the matching layout.

The automatic pipeline normally works per word, and can also merge a safe run of 2-3 wrong-layout words separated by spaces into one replacement. It does not rewrite an already typed sentence. For longer text, use Convert selected text: select the exact text, press the hotkey, and the app replaces that selection.

Supported language directions:
• English ⇄ Russian
• English ⇄ Ukrainian
• English ⇄ Romanian
• Romanian ASCII → Romanian with diacritics, when enabled

## first-setup

On first launch, open Setup from the menu bar and complete these checks:

1. Grant Accessibility permission. macOS requires this for global key monitoring and for posting replacement key events. Without it, LayoutSwitcher cannot correct text.
2. Enable the needed input sources in System Settings → Keyboard → Input Sources. You need English plus at least one target language: Russian, Ukrainian, or Romanian.
3. Make sure the target layout can type the characters you expect. Romanian diacritics require Romanian - Standard, not only an English layout.

The menu-bar badge shows the current macOS language code, such as EN, RU, UK, or RO. In app copy, Ukrainian is described as UA/Ukrainian to avoid confusing it with United Kingdom English; internally macOS still reports the Ukrainian language code as "uk".

If Accessibility was granted but the app still behaves as if it was not, remove LayoutSwitcher from System Settings → Privacy & Security → Accessibility, add it again, then restart the app.

## automatic-correction

The automatic flow is deliberately narrow:

1. Every keyDown is added to an in-memory word buffer.
2. Space or punctuation commits the current word.
3. Enter and Tab commit the word but do not trigger an automatic replacement, because they can send a message or move focus.
4. The detector scores the committed word across English, Russian, Ukrainian, and Romanian.
5. If the wrong-layout reading is clearly better, the app erases the word plus the separator, switches layout, and retypes the corrected word plus the same separator.
6. The word buffer is reset. Previous words are outside the buffer and are not touched.

Words containing digits are skipped. They are usually product names, versions, passwords, model numbers, or mixed technical text.

Technical tokens are also skipped: URLs, email addresses, @handles, file paths, and dotted package names are treated as non-convertible content.

Secure text fields are skipped entirely. When the focused element is a password field, the pipeline stops processing keystrokes.

The app also stops/reset buffers on focus changes, mouse clicks, modifier shortcuts, and other interactions that make the current text position uncertain.

## extending-corrections

LayoutSwitcher can correct more than one word at a time when adjacent words form a clear wrong-layout burst.

Sequence retype (always on):
When you keep typing two or three wrong-layout words in a row, separated by single spaces, and each one is confidently a switch on its own, the app merges them into one continuous erase-and-retype rather than firing per word. The replacement covers the whole run plus the final separator.

Auto-extend recent ambiguous words (opt-in):
Enable this in Preferences → Detection. When a long word triggers a switch, the pipeline looks back at the words you committed just before it and pulls in any that were ambiguous on their own but unambiguously belong to the same language as the trigger.

Example with the toggle on:
• You type "z nt,t " on the English layout.
• "z" alone is too short for a confident decision, so it commits as ambiguous.
• "nt,t" reads cleanly as Russian "тебе" and triggers the switch.
• Auto-extend re-evaluates "z" with single-character correction enabled, sees it maps to Russian "я", and includes it in the replacement.
• Result: "я тебе ".

Without the toggle, only the trigger word is retyped and "z" remains as it was.

Constraints on auto-extend:
• Up to four prior words within a two-second window.
• Same focused app — switching apps stops the walk.
• Words must be separated by plain spaces — Enter, Tab, or sentence-ending punctuation stop the walk.
• Already auto-switched words are skipped.

Convert single-character words (opt-in, separate toggle):
When this is on, the live detector also corrects a standalone single-character word the moment its separator commits, without needing a neighboring trigger. Useful for "я", "a", "и", "o", and similar particles.

Manual fallback:
If you want to correct a sentence the automatic pipeline missed — for example an older paragraph, or one that includes punctuation the detector treats as a boundary — press the Convert last sentence hotkey. It walks back from the latest word to the previous sentence break and converts the trailing run, using aggressive single-character mode.

## manual-actions

Current default hotkeys:

• Manual toggle of last word: ⌃⌥\\
• Force-retype last word: ⌃⌥⌘R
• Undo last automatic switch: ⌥⌘Z
• Convert selected text: ⌃⌥⌘L
• Snooze automatic switching: ⌃⌥⌘P

Manual toggle retypes the most recently committed word in the opposite layout. It is useful when the detector decided to keep a word but you wanted it switched. The safety window is 3 seconds and is cleared when focus moves to another app.

Force-retype last word re-runs the detector on the most recently committed word and retypes it if a different layout is detected. Unlike manual toggle, it does not have a safety window and can be used at any time to correct a word that escaped automatic switching.

Undo last automatic switch restores the original characters from the most recent automatic correction. The undo window is also 3 seconds and is locked to the same app where the correction happened.

Convert selected text is for multi-word fixes. It does not depend on the word buffer: you select a word, sentence, or paragraph and the app replaces that exact plain-text selection.

Snooze temporarily pauses automatic switching for the configured duration. Manual actions still work, and the menu-bar badge shows the remaining pause as P<minutes>.

The Hotkeys tab now allows rebinding shortcuts directly. If you assign a shortcut already used by another action, the old binding is removed automatically.

## selection-conversion

Convert selected text is the recommended multi-word workflow.

Flow:
1. Select the exact text you want to fix.
2. Press ⌃⌥⌘L.
3. LayoutSwitcher reads the selected plain text.
4. It tries likely language directions and chooses the conversion with the strongest dictionary/ngram score.
5. It replaces only the current selection.

The primary path uses Accessibility selected-text read/write. If the focused app does not support that, LayoutSwitcher falls back to a clipboard path: it saves the current clipboard, sends Copy, converts the copied plain text, sends Paste, then restores the original clipboard contents.

This feature intentionally does not preserve rich formatting. It works with plain text.

The selected text length limit is configurable in Preferences → General → Selection conversion. Default: 5000 characters. Minimum: 100. Maximum: 20000. The hard maximum exists so an accidental huge selection cannot trigger a long, disruptive replacement.

Conversion is skipped in secure fields, empty selections, selections above the configured limit, and cases where no confident opposite-layout candidate is found.

## preferences

General:
• Enable LayoutSwitcher turns the automatic pipeline on or off.
• Current layout shows the latest observed macOS input source.
• Accessibility shows whether macOS currently trusts the app.
• Last action shows the latest correction, skip reason, or failure.
• Auto-add Romanian diacritics enables Romanian ASCII → diacritics conversion.
• Correction aggressiveness controls detector thresholds: Conservative, Balanced, or Aggressive.
• Snooze duration controls how long the pause hotkey mutes automatic switching.
• Maximum selected characters controls the manual selection conversion limit.
• Statistics show today's and all-time auto-switches, manual switches, committed words, and saved characters.

Layouts:
• Shows current and enabled input sources.
• Shows detected language pairs, such as Russian ⇄ English, Ukrainian ⇄ English, Romanian ⇄ English.

Hotkeys:
• Shows the current default bindings for manual actions.

Exclusions:
• Lets you add apps where automatic erase/retype should never run.

Dictionaries:
• Lets you add words that should count as valid for each language.

About:
• App identity and short description.

## languages

LayoutSwitcher works with language IDs, not country variants:

• EN: English input sources such as ABC or U.S.
• RU: Russian input sources.
• UA: Ukrainian input sources. macOS and ISO language tags use "uk" internally; this means Ukrainian, not United Kingdom English.
• RO: Romanian input sources.

English acts as the alternate side for the current supported pairs:
• Russian ⇄ English
• Ukrainian ⇄ English
• Romanian ⇄ English

The detector can score all supported languages, but actual retyping still needs a matching enabled macOS input source. If the target layout is missing, the app aborts before erasing anything.

Romanian diacritics are special: if the corrected text contains Romanian-specific characters, the app needs a Romanian layout that can type them.

## romanian-diacritics

Auto-add Romanian diacritics is an optional General setting.

When enabled, the detector can upgrade plain Romanian ASCII forms:
• "buna" → "bună"
• "tara" → "țară"
• "casa" → "casă"

Conditions:
• The active language must be Romanian.
• Romanian - Standard must be enabled if the result contains Romanian diacritics.
• The word must not be present in your Romanian user dictionary as an explicit plain form.

Add words to the Romanian dictionary when you intentionally want a plain ASCII spelling to remain unchanged, for example names, identifiers, or project-specific terms.

## user-dictionaries

Each supported language has its own user dictionary.

A word added to a language dictionary is treated as valid for that language. That helps the detector avoid changing things you intentionally type.

Good candidates:
• Names and surnames.
• Brand names.
• Project names.
• Technical commands and product terms.
• Romanian ASCII words that should not receive diacritics.

Dictionaries are local. They are stored with your app settings and are not uploaded anywhere.

## exclusions

Some apps should not receive automatic erase/retype events: terminals, password managers, games, some IDEs, and apps with custom input handling.

Add those apps in Preferences → Exclusions. When an excluded app is focused, automatic corrections are suppressed before any erase happens.

You can also add an app from the menu bar:
1. Open Recent auto-switches.
2. Hover a recent entry from that app.
3. Choose Add <App> to exclusions.

Manual selection conversion is separate from automatic correction. It still requires an explicit hotkey and an explicit selection.

## privacy

LayoutSwitcher is local-first:

• It does not send typed text to a server.
• It does not use telemetry or analytics.
• It does not save the live keystroke buffer to disk.
• It resets the word buffer at word boundaries and unsafe interaction boundaries.
• It skips secure text fields.

Accessibility permission is required to observe keyboard events and retype corrections. Synthetic events are used only to replace the last committed word after a layout mistake.

Stored locally:
• Preferences.
• User dictionaries.
• Excluded bundle IDs.
• Recent switch history shown in the menu bar.
• Usage counters.

Automatic corrections can be disabled for selected apps in Preferences → Exclusions.

Clipboard fallback for Convert selected text temporarily uses the system clipboard. The app saves the current pasteboard items, performs Copy/Paste for the selected text, then restores the original clipboard contents.

Automatic correction is intentionally per-word because long automatic backspacing is risky in third-party apps. Multi-word correction is manual and selection-based so the user defines the boundaries.

## troubleshooting

Nothing happens while typing:
1. Check menu bar → Accessibility. It must say granted.
2. Check that Enable LayoutSwitcher is on.
3. Check that at least two macOS input sources are enabled.
4. Check that the current app is not in Exclusions.
5. Check that the field is not a secure/password field.

The wrong word was kept:
• Press manual toggle within 3 seconds.
• Add missing real words to the appropriate user dictionary.
• If the detector is too cautious, try Conservative, Balanced, or Aggressive.

A valid word was changed:
• Press Undo last automatic switch within 3 seconds.
• Add the word to the relevant user dictionary.
• If this happens often, use Conservative.

Convert selected text does not work:
• Make sure text is actually selected.
• Check that the selection is below the configured character limit.
• Try a smaller selection if the target app blocks Accessibility selected-text APIs.
• Avoid secure fields and apps that block copy/paste automation.

Romanian diacritics do not work:
• Enable Auto-add Romanian diacritics.
• Switch to Romanian before typing.
• Enable Romanian - Standard in macOS input sources.

Layout got stuck:
• Select the desired layout from the macOS input-source menu, then continue typing.
• This usually means macOS rejected a layout switch mid-flight.
