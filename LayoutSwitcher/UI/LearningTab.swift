import SwiftUI

/// Tab that displays learned exceptions (user-undone auto-switches) and allows
/// individual deletion or a full clear.
struct LearningTab: View {
    let learningCache: LearningCache
    @State private var entries: [LearningCache.LearnedEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if entries.isEmpty {
                emptyState
            } else {
                listWithHeader
            }
        }
        .onAppear(perform: refresh)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "graduationcap")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(String(localized: "settings.learning.empty-title"))
                .foregroundStyle(.secondary)
            Text(String(localized: "settings.learning.empty-description"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var listWithHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(format: String(localized: "settings.learning.count-format"), entries.count))
                    .font(.headline)
                Spacer()
                Button(role: .destructive, action: clearAll) {
                    Label(String(localized: "settings.learning.clear-all"), systemImage: "trash")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            List {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entry.original) → \(entry.corrected)")
                            .font(.body)
                        HStack(spacing: 4) {
                            Text("\(entry.sourceLanguage) → \(entry.targetLanguage)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let bundleID = entry.bundleID {
                                Text("•")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(bundleID)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(entry.timestamp, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onDelete(perform: delete)
            }
            .listStyle(.plain)
        }
    }

    private func refresh() {
        entries = learningCache.allEntries()
    }

    private func delete(at offsets: IndexSet) {
        let indices = Array(offsets).sorted(by: >)
        for index in indices {
            learningCache.remove(at: index)
        }
        refresh()
    }

    private func clearAll() {
        learningCache.removeAll()
        refresh()
    }
}
