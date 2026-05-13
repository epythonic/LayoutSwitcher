import AppKit
import SwiftUI

/// Settings tab showing every auto/manual switch with filters and clear action.
struct HistoryTab: View {
    @Bindable var recents: RecentSwitches
    @State private var filter: KindFilter = .all
    @State private var appFilter: String = ""
    private let clipboardWrite: @MainActor (String) -> Void

    init(
        recents: RecentSwitches,
        clipboardWrite: @escaping @MainActor (String) -> Void = { payload in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(payload, forType: .string)
        }
    ) {
        self.recents = recents
        self.clipboardWrite = clipboardWrite
    }

    /// Filter selector for switch kind (auto / manual / all).
    enum KindFilter: String, CaseIterable, Identifiable, Sendable {
        case all, auto, manual
        var id: Self { self }

        var localizedTitle: String {
            switch self {
            case .all: String(localized: "settings.history.filter.all")
            case .auto: String(localized: "settings.history.filter.auto")
            case .manual: String(localized: "settings.history.filter.manual")
            }
        }
    }

    /// Renders filters bar + history table + clear/export controls.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "settings.history.description"))
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Picker(String(localized: "settings.history.filter.kind"), selection: $filter) {
                    ForEach(KindFilter.allCases) { f in
                        Text(f.localizedTitle).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                TextField(String(localized: "settings.history.filter.app"), text: $appFilter)
                    .textFieldStyle(.roundedBorder)
                Spacer()
            }

            Table(filteredEntries) {
                TableColumn(String(localized: "settings.history.column.time")) { entry in
                    Text(Self.timestampFormatter.string(from: entry.timestamp))
                        .font(.caption.monospaced())
                }
                .width(min: 80, ideal: 100)

                TableColumn(String(localized: "settings.history.column.app")) { entry in
                    Text(entry.bundleName ?? entry.bundleID ?? "—")
                        .lineLimit(1)
                }
                .width(min: 100, ideal: 140)

                TableColumn(String(localized: "settings.history.column.original")) { entry in
                    Text(entry.original)
                        .lineLimit(1)
                }
                .width(min: 100, ideal: 140)

                TableColumn(String(localized: "settings.history.column.corrected")) { entry in
                    Text(entry.corrected)
                        .lineLimit(1)
                }
                .width(min: 100, ideal: 140)

                TableColumn(String(localized: "settings.history.column.kind")) { entry in
                    Text(entry.kind == .auto
                         ? String(localized: "settings.history.filter.auto")
                         : String(localized: "settings.history.filter.manual"))
                        .font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(entry.kind == .auto ? Color.green.opacity(0.2) : Color.blue.opacity(0.2),
                                    in: Capsule())
                }
                .width(min: 60, ideal: 80)
            }
            .frame(minHeight: 360)

            HStack {
                Text(String(format: String(localized: "settings.history.count"), filteredEntries.count, recents.entries.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: copyToClipboard) {
                    Label(String(localized: "settings.history.copy"), systemImage: "doc.on.clipboard")
                }
                Button(String(localized: "settings.history.clear"), role: .destructive) {
                    recents.clear()
                }
                .disabled(recents.entries.isEmpty)
            }
        }
        .padding()
    }

    /// Visible entries after applying kind + app substring filters.
    private var filteredEntries: [RecentSwitchEntry] {
        recents.entries.filter { entry in
            let kindMatches: Bool
            switch filter {
            case .all: kindMatches = true
            case .auto: kindMatches = entry.kind == .auto
            case .manual: kindMatches = entry.kind == .manual
            }
            guard kindMatches else { return false }
            if appFilter.isEmpty { return true }
            let needle = appFilter.lowercased()
            if let name = entry.bundleName, name.lowercased().contains(needle) { return true }
            if let id = entry.bundleID, id.lowercased().contains(needle) { return true }
            return false
        }
    }

    /// Serializes current filtered view to TSV-like text and copies onto pasteboard.
    private func copyToClipboard() {
        clipboardWrite(Self.exportPayload(for: filteredEntries))
    }

    /// Builds TSV-like export payload for recent switch entries.
    static func exportPayload(
        for entries: [RecentSwitchEntry],
        formatter: DateFormatter = Self.exportFormatter
    ) -> String {
        let header = "time\tapp\toriginal\tcorrected\tkind"
        let body = entries.map { entry in
            let time = formatter.string(from: entry.timestamp)
            let app = entry.bundleName ?? entry.bundleID ?? ""
            let kind = entry.kind == .auto ? "auto" : "manual"
            return "\(time)\t\(app)\t\(entry.original)\t\(entry.corrected)\t\(kind)"
        }.joined(separator: "\n")
        return ([header] + [body]).joined(separator: "\n")
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let exportFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
}
