# LayoutSwitcher AI Agent Rules

> This document governs how AI assistants interact with this project.

---

## 1. Communication Language

- **With the user:** Russian
- **Code identifiers, comments, logs, documentation:** English only
- **User-facing strings:** Localized (en, ru, ro, uk via `Localizable.strings`)

---

## 2. Swift Concurrency & Safety

- **Swift 6 strict concurrency is mandatory.**
- All shared mutable state must be isolated to `@MainActor`.
- Use `Sendable` conformance for value types crossing isolation boundaries.
- Prefer `struct` (value semantics) by default.
- Use `final class` only when necessary:
  - `@Observable` UI-bound models (`AppState`, `UsageStats`)
  - Shared mutable state with identity (`WordBuffer`, `TypingPipeline`)
- **Never use `!` (force unwrap).** Use `guard let`, `if let`, `??`, or explicit nil-handling.
- Capture `[weak self]` in all closures that reference `self` to avoid retain cycles.

---

## 3. Dependency Injection & Testability

- Every service class must expose a designated initializer with **injected closures for all side effects**.
- Default closure implementations use production dependencies; tests inject deterministic stubs.
- Example pattern from `Retyper`:

  ```swift
  init(
      mapping: any KeyboardMapping,
      inputSources: InputSourceManager,
      enabledLayoutsProvider: (() -> [RetypeInputSource])? = nil,
      currentLayoutIDProvider: (() -> String?)? = nil,
      // ... more closures
  )
  ```

- Never use singletons or global state directly. Always inject through initializers.

---

## 4. Logging

- Use `os.Logger` exclusively:

  ```swift
  static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "CategoryName")
  ```

- **Always annotate user data with `privacy: .public`** so logs are readable in Console:

  ```swift
  Self.logger.debug("committed \"\(word.text, privacy: .public)\"")
  ```

- Category names are PascalCase (e.g., `"Pipeline"`, `"Detector"`, `"Retyper"`, `"EventTap"`).

---

## 5. Error Handling

- **Do not use `throws` for recoverable domain errors.**
- Return `Result`-like enums with explicit failure reasons:

  ```swift
  enum RetypeResult: Equatable {
      case success
      case failure(RetypeFailureReason)
  }
  ```

- Use optionals for missing data, never force unwrap.

---

## 6. Naming Conventions

- Types: PascalCase (`TypingPipeline`, `LayoutDetector`)
- Functions / variables / properties: camelCase (`autoAddRomanianDiacritics`, `recordWordCommitted`)
- Static members: accessed via `Self.` prefix (`Self.logger`, `Self.sequenceLookaheadDelay`)
- Private static constants: camelCase starting with the type's concern (`sequenceLookaheadDelay`, `safeFinalPunctuation`)
- UserDefaults keys: dot-namespaced (`"settings.autoAddRomanianDiacritics"`, `"stats.autoTotal"`)
- Test names: descriptive sentence (`autoSwitchRecordsOnlyAfterSuccessfulRetype`)

---

## 7. Documentation Style

- Use Swift DocC `///` for all public API (types, methods, properties).
- First line is a concise summary. Additional lines explain rationale or constraints.
- Example:

  ```swift
  /// Mutable buffer that accumulates typed characters until separator commit.
  @MainActor
  final class WordBuffer { ... }
  ```

- Inline comments explain *why*, not *what*. The code should be self-describing.

---

## 8. Testing Rules

- **Framework:** Swift Testing (`import Testing`). No XCTest in new tests.
- Tests are `@MainActor struct` with `@Test` functions.
- Assertions use `#expect()` (not `XCTAssert`).
- Fixtures inject all dependencies via the DI initializer pattern.
- Tests must be deterministic: no `Thread.sleep`, no uncontrolled delays.
- Use injected `sleep` closures or `ControlledEvaluationDelay` for async timing.
- No tests should depend on system state (real keyboard layouts, real pasteboard, Accessibility grants).
- Fake / stub types are declared as `private struct` inside the test struct.

---

## 9. UI & Observation Patterns

- UI-bound models use `@Observable` (not `@ObservableObject` / `ObservableObject`).
- Views use `@Bindable var` for two-way binding.
- Settings keys are persisted via `UserDefaults` with `didSet` observers, never external save buttons.
- Day-rollover logic (e.g., stats) is handled inside the model, not in the view layer.

---

## 10. Build & Verification Discipline

- **Zero errors, zero warnings** on `xcodebuild build`.
- **`** TEST SUCCEEDED **`** on `xcodebuild test`.
- Run full test suite after every batch of changes.
- Targeted tests first, then full suite.
- Use `todo_list` to track recovery / implementation steps.

---

## 11. Recovery & Project Hygiene

- **Do not modify** raw recovery sources in `RecoveryArtifacts/RawRecoveredSwift/`.
- Only the working project directory (`LayoutSwitcher/`, `LayoutSwitcherTests/`) is editable.
- Recovered modules are added in logical batches.
- Each batch ends with: build → targeted tests → full test suite → update inventory.

---

## 12. Patterns Inferred from Codebase (Apply These)

- **Privacy-first logging:** Any string containing user input must have `privacy: .public`.
- **Separator safety:** `.enter` and `.tab` suppress auto-switch to avoid accidental form submission.
- **Bundle ID tracking:** Every committed word carries `bundleID` for app-specific exclusion logic.
- **LanguageID as enum:** Languages are `.en`, `.ru`, `.uk`, `.ro` — never raw strings in business logic.
- **WordChar / CommittedWord as value types:** Immutable snapshots; pipeline owns mutable buffers.
- **RetypeResult is async:** All retype operations are `async` to allow layout confirmation delays.
- **HotkeyCoordinator is single-responsibility:** Routes hotkey actions, tracks undo state, does not touch event taps directly.
