import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct HistoryTabTests {
    private static func fixedID(_ byte: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte))
    }

    @Test func exportPayloadContainsHeaderAndRows() {
        let entries = [
            RecentSwitchEntry(
                id: Self.fixedID(1),
                original: "ghbdtn",
                corrected: "привет",
                bundleID: "com.test.app",
                bundleName: "Test App",
                kind: .auto,
                timestamp: Date(timeIntervalSince1970: 0)
            ),
            RecentSwitchEntry(
                id: Self.fixedID(2),
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
            timestampStringProvider: Self.testTimestampString
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
            timestampStringProvider: Self.testTimestampString
        )

        #expect(payload == "time\tapp\toriginal\tcorrected\tkind\n")
    }

    private static func testTimestampString(for date: Date) -> String {
        switch Int(date.timeIntervalSince1970) {
        case 0:
            return "1970-01-01 00:00:00"
        case 60:
            return "1970-01-01 00:01:00"
        default:
            return "unexpected"
        }
    }
}
