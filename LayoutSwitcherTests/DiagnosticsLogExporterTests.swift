import Foundation
import Testing
@testable import LayoutSwitcher

@MainActor
struct DiagnosticsLogExporterTests {
    private enum TestError: Error {
        case failed
    }

    @Test func exportResultRunsLogShowWithExpectedArgumentsAndWritesData() async {
        let payload = Data("diagnostic logs".utf8)
        let targetURL = URL(fileURLWithPath: "/tmp/layoutswitcher-diagnostics.log")
        var capturedArguments: [String] = []
        var capturedData: Data?
        var capturedURL: URL?

        let exporter = DiagnosticsLogExporter(
            runLogShow: { arguments in
                capturedArguments = arguments
                return payload
            },
            writeData: { data, url in
                capturedData = data
                capturedURL = url
            }
        )

        #expect(await exporter.exportResult(to: targetURL) == .success)
        #expect(capturedArguments == DiagnosticsLogExporter.defaultArguments)
        #expect(capturedData == payload)
        #expect(capturedURL == targetURL)
    }

    @Test func exportResultReportsLogShowFailureAndSkipsWrite() async {
        var writeCount = 0
        let exporter = DiagnosticsLogExporter(
            runLogShow: { _ in throw TestError.failed },
            writeData: { _, _ in writeCount += 1 }
        )

        let targetURL = URL(fileURLWithPath: "/tmp/layoutswitcher-diagnostics.log")

        let result = await exporter.exportResult(to: targetURL)

        guard case .failure(.logShowFailed(let message)) = result else {
            #expect(Bool(false))
            return
        }

        #expect(!message.isEmpty)
        #expect(writeCount == 0)
    }

    @Test func exportResultReportsWriteFailure() async {
        let exporter = DiagnosticsLogExporter(
            runLogShow: { _ in Data("diagnostic logs".utf8) },
            writeData: { _, _ in throw TestError.failed }
        )

        let targetURL = URL(fileURLWithPath: "/tmp/layoutswitcher-diagnostics.log")

        let result = await exporter.exportResult(to: targetURL)

        guard case .failure(.writeFailed(let message)) = result else {
            #expect(Bool(false))
            return
        }

        #expect(!message.isEmpty)
    }

    @Test func exportKeepsBooleanCompatibility() async {
        let exporter = DiagnosticsLogExporter(
            runLogShow: { _ in Data("diagnostic logs".utf8) },
            writeData: { _, _ in }
        )

        let targetURL = URL(fileURLWithPath: "/tmp/layoutswitcher-diagnostics.log")

        #expect(await exporter.export(to: targetURL))
    }

    @Test func checkedOutputReturnsDataForSuccessfulStatus() throws {
        let payload = Data("diagnostic logs".utf8)

        let checked = try DiagnosticsLogExporter.checkedOutput(payload, terminationStatus: 0)

        #expect(checked == payload)
    }

    @Test func checkedOutputThrowsForFailedStatus() {
        #expect(throws: DiagnosticsLogExporter.LogShowFailure(status: 2)) {
            try DiagnosticsLogExporter.checkedOutput(Data(), terminationStatus: 2)
        }
    }
}
