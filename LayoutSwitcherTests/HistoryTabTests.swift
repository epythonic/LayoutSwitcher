import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct HistoryTabTests {
    @Test func exportPayloadContainsHeaderAndRows() {
        let entries = [
            RecentSwitchEntry(
                original: "ghbdtn",
                corrected: "привет",
                bundleID: "com.test.app",
                bundleName: "Test App",
                kind: .auto,
                timestamp: Date(timeIntervalSince1970: 0)
            ),
            RecentSwitchEntry(
                original: "rfr",
                corrected: "как",
                bundleID: "com.test.other",
                bundleName: nil,
                kind: .manual,
                timestamp: Date(timeIntervalSince1970: 60)
            ),
        ]

        let payload = HistoryTab.exportPayload(
            for: entries,
            formatter: Self.makeFormatter()
        )

        #expect(payload == """
        time\tapp\toriginal\tcorrected\tkind
        1970-01-01 00:00:00\tTest App\tghbdtn\tпривет\tauto
        1970-01-01 00:01:00\tcom.test.other\trfr\tкак\tmanual
        """)
    }

    @Test func exportPayloadKeepsHeaderWhenEntriesAreEmpty() {
        let payload = HistoryTab.exportPayload(
            for: [],
            formatter: Self.makeFormatter()
        )

        #expect(payload == "time\tapp\toriginal\tcorrected\tkind\n")
    }

    private static func makeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }
}
