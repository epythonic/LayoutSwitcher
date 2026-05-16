import SwiftUI

/// Settings tab showing currently enabled system layouts and detected switch pairs.
struct LayoutsTab: View {
    /// Shared settings model that persists user-selected correction directions.
    @Bindable var appState: AppState
    /// Input source manager that provides current and enabled layout snapshots.
    @Bindable var inputSources: InputSourceManager

    /// Renders active layouts list and auto-detected language pairs.
    var body: some View {
        let current = inputSources.currentSnapshot
        let enabledLayouts = inputSources.enabledLayoutSnapshots()
        let detectedPairs = LayoutPairResolver.autoDetectSnapshots(from: enabledLayouts)
        let detectedLanguagePairs = detectedPairs.map(\.languagePair)
        let selectablePairs = Self.selectablePairs(
            active: appState.activeLanguagePair,
            detected: detectedLanguagePairs
        )
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "settings.layouts.active-title"))
                .font(.headline)
            Text(String(localized: "settings.layouts.description"))
                .font(.callout)
                .foregroundStyle(.secondary)

            if let current {
                LabeledContent(String(localized: "settings.layouts.current")) {
                    Text(Self.localizedParenthesizedPair(current.localizedName, current.primaryLanguage ?? "?"))
                        .font(.body.monospaced())
                }
                .padding(.vertical, 4)
            }

            List(enabledLayouts, id: \.id) { source in
                HStack(spacing: 12) {
                    Image(systemName: "keyboard")
                        .foregroundStyle(source.id == current?.id ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.localizedName)
                        Text(source.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text((source.primaryLanguage ?? "?").uppercased())
                        .font(.caption.monospaced())
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            .frame(minHeight: 220)

            Text(String(localized: "settings.layouts.detected-pairs"))
                .font(.headline)
                .padding(.top, 8)
            ForEach(detectedPairs, id: \.languagePair) { pair in
                HStack {
                    Text(pair.languagePair.rawValue.uppercased())
                        .font(.caption.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.tint.opacity(0.2), in: Capsule())
                    Text(Self.localizedBidirectionalPair(pair.primary.localizedName, pair.alternate.localizedName))
                        .foregroundStyle(.secondary)
                }
            }

            Text(String(localized: "settings.layouts.active-pair"))
                .font(.headline)
                .padding(.top, 8)
            Text(String(localized: "settings.layouts.active-pair-description"))
                .font(.callout)
                .foregroundStyle(.secondary)
            if selectablePairs.isEmpty {
                Text(String(localized: "settings.layouts.language-directions-empty"))
                    .foregroundStyle(.secondary)
            } else {
                Picker(String(localized: "settings.layouts.active-pair"), selection: $appState.activeLanguagePair) {
                    ForEach(selectablePairs, id: \.self) { pair in
                        Text(pair.localizedTitle).tag(pair)
                    }
                }
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier("settings.layouts.active-pair")
                if !detectedLanguagePairs.contains(appState.activeLanguagePair) {
                    Text(String(localized: "settings.layouts.active-pair-unavailable"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }

    private static func selectablePairs(active: LanguagePair, detected: [LanguagePair]) -> [LanguagePair] {
        if detected.contains(active) {
            return detected
        }
        return [active] + detected
    }

    private static func localizedParenthesizedPair(_ leading: String, _ trailing: String) -> String {
        String(format: NSLocalizedString("%@ (%@)", comment: "A value followed by another value in parentheses."), leading, trailing)
    }

    private static func localizedBidirectionalPair(_ leading: String, _ trailing: String) -> String {
        String(format: NSLocalizedString("%@ ↔ %@", comment: "Two values separated by a bidirectional arrow."), leading, trailing)
    }
}

/// Stable SwiftUI identity for language-pair rows.
extension LanguagePair: Identifiable {
    /// Uses persisted raw value as stable identity.
    var id: String { rawValue }
}
