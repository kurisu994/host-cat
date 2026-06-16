import XCTest
@testable import HostCatCore

final class DiagnosticLogExporterTests: XCTestCase {
    func testExporterWritesFormattedDiagnosticLogFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("HostCat-Diagnostics.log")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recordDate = Date(timeIntervalSince1970: 1_799_999_940)
        let exporter = DiagnosticLogExporter(
            lookback: 60,
            now: { now },
            readRecords: { since, subsystemPrefixes in
                XCTAssertEqual(since, recordDate)
                XCTAssertEqual(subsystemPrefixes, ["com.hostcat."])
                return [
                    DiagnosticLogRecord(
                        date: recordDate,
                        level: .error,
                        subsystem: "com.hostcat.app",
                        category: "HostWriteCoordinator",
                        process: "HostCat",
                        message: "Write failed: hash mismatch"
                    )
                ]
            }
        )

        let result = try exporter.export(to: destination)
        let text = try String(contentsOf: destination, encoding: .utf8)

        XCTAssertEqual(result.recordCount, 1)
        XCTAssertEqual(result.destinationURL, destination)
        XCTAssertTrue(text.contains("HostCat Diagnostic Logs"))
        XCTAssertTrue(text.contains("records: 1"))
        XCTAssertTrue(text.contains("[error] com.hostcat.app/HostWriteCoordinator (HostCat) Write failed: hash mismatch"))
    }

    func testFormatterShowsEmptyStateWhenNoRecordsExist() {
        let text = DiagnosticLogFormatter.format(
            records: [],
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            since: Date(timeIntervalSince1970: 1_799_996_400),
            subsystemPrefixes: ["com.hostcat."]
        )

        XCTAssertTrue(text.contains("records: 0"))
        XCTAssertTrue(text.contains("No HostCat log entries were found"))
    }

    func testDiagnosticLogLevelUsesSupportedNames() {
        XCTAssertEqual(DiagnosticLogLevel.error.rawValue, "error")
        XCTAssertEqual(DiagnosticLogLevel.warning.rawValue, "warning")
        XCTAssertEqual(DiagnosticLogLevel.info.rawValue, "info")
        XCTAssertEqual(DiagnosticLogLevel.debug.rawValue, "debug")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HostCatCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
