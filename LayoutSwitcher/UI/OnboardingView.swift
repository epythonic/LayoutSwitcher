import SwiftUI

/// First-run setup flow that guides user through accessibility permission grant,
/// layout pair confirmation, hotkey overview, and a live typing sandbox.
struct OnboardingView: View {
    @Bindable var permission: AccessibilityPermission
    @Bindable var inputSources: InputSourceManager
    @Bindable var hotkeyRegistry: HotkeyRegistry
    let onFinish: () -> Void

    @State private var step: Step = .welcome
    @State private var sandboxText: String = ""

    /// Sequential onboarding stages.
    enum Step { case welcome, accessibility, layouts, hotkeys, sandbox, done }

    /// Renders current onboarding step and action controls.
    var body: some View {
        VStack(spacing: 24) {
            content
            Spacer()
            navigation
        }
        .padding(32)
        .frame(width: 560, height: 420)
        .onChange(of: permission.isTrusted) { _, granted in
            if granted, step == .accessibility {
                step = .layouts
            }
        }
    }

    /// Step-specific primary content.
    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            VStack(spacing: 16) {
                Image(systemName: "keyboard")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text(String(localized: "onboarding.welcome.title"))
                    .font(.title).bold()
                Text(String(localized: "onboarding.welcome.subtitle"))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        case .accessibility:
            VStack(spacing: 16) {
                Image(systemName: permission.isTrusted ? "checkmark.shield.fill" : "lock.shield")
                    .font(.system(size: 56))
                    .foregroundStyle(permission.isTrusted ? .green : .orange)
                Text(String(localized: "onboarding.accessibility.title"))
                    .font(.title2).bold()
                Text(String(localized: "onboarding.accessibility.subtitle"))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if permission.isTrusted {
                    Label(String(localized: "onboarding.accessibility.granted"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    HStack(spacing: 12) {
                        Button(String(localized: "onboarding.accessibility.open-settings")) {
                            permission.openSystemSettings()
                            permission.promptForTrust()
                        }
                        .buttonStyle(.borderedProminent)
                        Button(String(localized: "onboarding.accessibility.recheck")) {
                            permission.refresh()
                        }
                    }
                }
            }
        case .layouts:
            VStack(spacing: 16) {
                Image(systemName: "globe")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text(String(localized: "onboarding.layouts.title"))
                    .font(.title2).bold()
                Text(String(localized: "onboarding.layouts.subtitle"))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                let layouts = inputSources.enabledLayouts()
                if layouts.isEmpty {
                    Text(String(localized: "onboarding.layouts.none"))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(layouts, id: \.id) { layout in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(layout.localizedName)
                                    .font(.body)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        case .hotkeys:
            VStack(spacing: 16) {
                Image(systemName: "command")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text(String(localized: "onboarding.hotkeys.title"))
                    .font(.title2).bold()
                Text(String(localized: "onboarding.hotkeys.subtitle"))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(HotkeyAction.ordered, id: \.self) { action in
                        if let definition = hotkeyRegistry.binding(for: action) {
                            hotkeyRow(action.localizedTitle, key: definition.displayText)
                        }
                    }
                }
                .padding(.horizontal)
            }
        case .sandbox:
            VStack(spacing: 16) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text(String(localized: "onboarding.sandbox.title"))
                    .font(.title2).bold()
                Text(String(localized: "onboarding.sandbox.subtitle"))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                TextField(String(localized: "onboarding.sandbox.placeholder"), text: $sandboxText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                Text(String(localized: "onboarding.sandbox.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        case .done:
            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text(String(localized: "onboarding.done.title"))
                    .font(.title).bold()
                Text(String(localized: "onboarding.done.subtitle"))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Helper to render a single hotkey description row.
    private func hotkeyRow(_ action: String, key: String) -> some View {
        HStack {
            Text(action)
                .font(.callout)
            Spacer()
            Text(key)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    /// Bottom navigation controls for step transitions.
    @ViewBuilder
    private var navigation: some View {
        HStack {
            if step != .welcome {
                Button(String(localized: "onboarding.button.back")) { back() }
            }
            Spacer()
            Button(primaryTitle) { primaryAction() }
                .keyboardShortcut(.defaultAction)
                .disabled(primaryDisabled)
        }
    }

    /// Dynamic title for primary action button.
    private var primaryTitle: String {
        switch step {
        case .welcome: String(localized: "onboarding.button.continue")
        case .accessibility:
            permission.isTrusted ? String(localized: "onboarding.button.continue") : String(localized: "onboarding.button.continue-once-granted")
        case .layouts: String(localized: "onboarding.button.continue")
        case .hotkeys: String(localized: "onboarding.button.continue")
        case .sandbox: String(localized: "onboarding.button.continue")
        case .done: String(localized: "onboarding.button.finish")
        }
    }

    /// Whether primary action should be disabled for current state.
    private var primaryDisabled: Bool {
        step == .accessibility && !permission.isTrusted
    }

    /// Advances onboarding state and executes side effects for each stage.
    private func primaryAction() {
        switch step {
        case .welcome:
            step = .accessibility
            permission.startPolling()
        case .accessibility:
            step = .layouts
        case .layouts:
            step = .hotkeys
        case .hotkeys:
            step = .sandbox
        case .sandbox:
            step = .done
        case .done:
            permission.stopPolling()
            onFinish()
        }
    }

    /// Moves one step backwards where applicable.
    private func back() {
        switch step {
        case .accessibility: step = .welcome
        case .layouts: step = .accessibility
        case .hotkeys: step = .layouts
        case .sandbox: step = .hotkeys
        case .done: step = .sandbox
        case .welcome: break
        }
    }
}
