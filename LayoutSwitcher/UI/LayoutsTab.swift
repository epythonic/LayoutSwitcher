import SwiftUI

/// Settings tab showing currently enabled system layouts and detected switch pairs.
struct LayoutsTab: View {
    @Bindable var inputSources: InputSourceManager

    /// Renders active layouts list and auto-detected language pairs.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "settings.layouts.active-title"))
                .font(.headline)
            Text(String(localized: "settings.layouts.description"))
                .font(.callout)
                .foregroundStyle(.secondary)

            if let current = inputSources.current {
                LabeledContent(String(localized: "settings.layouts.current")) {
                    Text("\(current.localizedName) (\(current.primaryLanguage ?? "?"))")
                        .font(.body.monospaced())
                }
                .padding(.vertical, 4)
            }

            List(inputSources.enabledLayouts(), id: \.id) { source in
                HStack(spacing: 12) {
                    Image(systemName: "keyboard")
                        .foregroundStyle(source.id == inputSources.current?.id ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
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
            ForEach(LayoutPairResolver.autoDetect(from: inputSources.enabledLayouts()), id: \.languagePair) { pair in
                HStack {
                    Text(pair.languagePair.rawValue.uppercased())
                        .font(.caption.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.tint.opacity(0.2), in: Capsule())
                    Text("\(pair.primary.localizedName) ↔ \(pair.alternate.localizedName)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}

/// Stable SwiftUI identity for language-pair rows.
extension LanguagePair: Identifiable {
    var id: String { rawValue }
}
