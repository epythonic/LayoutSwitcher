import Foundation
import os

/// Exports recent unified-log entries for tester diagnostics.
@MainActor
struct DiagnosticsLogExporter {
    typealias RunLogShow = @MainActor ([String]) async throws -> Data
    typealias WriteData = @MainActor (Data, URL) throws -> Void

    private static let logger = Logger(subsystem: "GM.LayoutSwitcher", category: "ExportLogs")

    /// Error returned when `/usr/bin/log show` exits unsuccessfully.
    struct LogShowFailure: LocalizedError, Equatable {
        /// Process termination status.
        let status: Int32

        /// Human-readable failure text for logs.
        var errorDescription: String? {
            "log show exited with status \(status)"
        }
    }

    /// Explicit export result for recoverable diagnostics failures.
    enum ExportResult: Equatable {
        case success
        case failure(ExportFailureReason)

        /// Boolean projection kept for existing UI call sites.
        var isSuccess: Bool {
            self == .success
        }
    }

    /// Recoverable failure reason surfaced by diagnostics export.
    enum ExportFailureReason: Equatable {
        case logShowFailed(String)
        case writeFailed(String)
    }

    /// Arguments used to export recent LayoutSwitcher unified-log entries.
    static let defaultArguments = [
        "show",
        "--predicate", "subsystem == 'GM.LayoutSwitcher'",
        "--info",
        "--last", "1h"
    ]

    /// Injected command runner for `log show`.
    private let runLogShow: RunLogShow
    /// Injected file writer for exported payload.
    private let writeData: WriteData

    /// Creates an exporter with injectable process and file-system side effects.
    init(
        runLogShow: @escaping RunLogShow = DiagnosticsLogExporter.runLogShowProcess(arguments:),
        writeData: @escaping WriteData = { data, url in
            try data.write(to: url)
        }
    ) {
        self.runLogShow = runLogShow
        self.writeData = writeData
    }

    /// Runs `log show` and writes the resulting payload to the selected URL.
    @discardableResult
    func export(to url: URL) async -> Bool {
        await exportResult(to: url).isSuccess
    }

    /// Runs `log show` and returns an explicit domain result.
    func exportResult(to url: URL) async -> ExportResult {
        do {
            let data = try await runLogShow(Self.defaultArguments)
            return writeExportedData(data, to: url)
        } catch {
            Self.logger.error("Export logs failed: \(error.localizedDescription, privacy: .public)")
            return .failure(.logShowFailed(error.localizedDescription))
        }
    }

    /// Writes already collected diagnostics data and returns an explicit domain result.
    private func writeExportedData(_ data: Data, to url: URL) -> ExportResult {
        do {
            try writeData(data, url)
            return .success
        } catch {
            Self.logger.error("Write diagnostics logs failed: \(error.localizedDescription, privacy: .public)")
            return .failure(.writeFailed(error.localizedDescription))
        }
    }

    private static func runLogShowProcess(arguments: [String]) async throws -> Data {
        try await Task.detached(priority: .utility) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            task.arguments = arguments

            let output = Pipe()
            task.standardOutput = output
            try task.run()

            let data = output.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return try checkedOutput(data, terminationStatus: task.terminationStatus)
        }.value
    }

    /// Returns output data only when the process status indicates success.
    nonisolated static func checkedOutput(_ data: Data, terminationStatus: Int32) throws -> Data {
        guard terminationStatus == 0 else {
            throw LogShowFailure(status: terminationStatus)
        }
        return data
    }
}
