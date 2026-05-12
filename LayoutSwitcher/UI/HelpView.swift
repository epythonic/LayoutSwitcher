import SwiftUI

/// Split-view help browser for static in-app documentation content.
struct HelpView: View {
    @State private var selectedSectionID: String = HelpContent.sections.first?.id ?? ""

    /// Currently selected section with fallback to first section for safety.
    private var selectedSection: HelpSection {
        HelpContent.sections.first(where: { $0.id == selectedSectionID }) ?? HelpContent.sections[0]
    }

    /// Renders section list and localized article body.
    var body: some View {
        NavigationSplitView {
            List(HelpContent.sections, selection: $selectedSectionID) { section in
                Text(section.localizedTitle)
                    .tag(section.id)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(selectedSection.localizedTitle)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.bottom, 4)

                    Text(selectedSection.localizedBody)
                        .font(.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}
