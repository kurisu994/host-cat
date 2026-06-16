import Foundation
import OSLog

/// HostCat 对外展示的诊断日志级别。
public enum DiagnosticLogLevel: String, CaseIterable, Sendable {
    case error
    case warning
    case info
    case debug
}

/// 一条可导出的 HostCat 诊断日志记录。
public struct DiagnosticLogRecord: Equatable, Sendable {
    public var date: Date
    public var level: DiagnosticLogLevel
    public var subsystem: String
    public var category: String
    public var process: String
    public var message: String

    public init(
        date: Date,
        level: DiagnosticLogLevel,
        subsystem: String,
        category: String,
        process: String,
        message: String
    ) {
        self.date = date
        self.level = level
        self.subsystem = subsystem
        self.category = category
        self.process = process
        self.message = message
    }
}

public struct DiagnosticLogExportResult: Equatable, Sendable {
    public var destinationURL: URL
    public var recordCount: Int

    public init(destinationURL: URL, recordCount: Int) {
        self.destinationURL = destinationURL
        self.recordCount = recordCount
    }
}

public typealias DiagnosticLogReadRecords = @Sendable (
    _ since: Date,
    _ subsystemPrefixes: [String]
) throws -> [DiagnosticLogRecord]

/// 将 HostCat 相关 OSLog 记录导出为可附到 issue / 邮件的纯文本诊断文件。
public struct DiagnosticLogExporter: Sendable {
    public static let defaultLookback: TimeInterval = 60 * 60
    public static let defaultSubsystemPrefixes = ["com.hostcat."]

    public var lookback: TimeInterval
    public var subsystemPrefixes: [String]

    private let now: @Sendable () -> Date
    private let readRecords: DiagnosticLogReadRecords

    public init(
        lookback: TimeInterval = Self.defaultLookback,
        subsystemPrefixes: [String] = Self.defaultSubsystemPrefixes,
        now: @escaping @Sendable () -> Date = Date.init,
        readRecords: DiagnosticLogReadRecords? = nil
    ) {
        self.lookback = lookback
        self.subsystemPrefixes = subsystemPrefixes
        self.now = now
        self.readRecords = readRecords ?? Self.readOSLogRecords
    }

    @discardableResult
    public func export(to destinationURL: URL) throws -> DiagnosticLogExportResult {
        let generatedAt = now()
        let since = generatedAt.addingTimeInterval(-lookback)
        let records = try readRecords(since, subsystemPrefixes)
            .sorted { $0.date < $1.date }
        let text = DiagnosticLogFormatter.format(
            records: records,
            generatedAt: generatedAt,
            since: since,
            subsystemPrefixes: subsystemPrefixes
        )

        try text.write(to: destinationURL, atomically: true, encoding: .utf8)

        return DiagnosticLogExportResult(
            destinationURL: destinationURL,
            recordCount: records.count
        )
    }

    private static func readOSLogRecords(
        since: Date,
        subsystemPrefixes: [String]
    ) throws -> [DiagnosticLogRecord] {
        let store = try makeLogStore()
        let position = store.position(date: since)
        let predicate = makeSubsystemPredicate(prefixes: subsystemPrefixes)
        let entries = try store.getEntries(at: position, matching: predicate)

        return entries.compactMap { entry in
            guard let logEntry = entry as? OSLogEntryLog else {
                return nil
            }

            return DiagnosticLogRecord(
                date: logEntry.date,
                level: normalizedLevel(from: logEntry.level),
                subsystem: logEntry.subsystem,
                category: logEntry.category,
                process: logEntry.process,
                message: logEntry.composedMessage
            )
        }
    }

    private static func makeLogStore() throws -> OSLogStore {
        do {
            return try OSLogStore(scope: .system)
        } catch {
            return try OSLogStore(scope: .currentProcessIdentifier)
        }
    }

    private static func makeSubsystemPredicate(prefixes: [String]) -> NSPredicate? {
        let predicates = prefixes.map {
            NSPredicate(format: "subsystem BEGINSWITH %@", $0)
        }
        guard !predicates.isEmpty else { return nil }
        return NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
    }

    private static func normalizedLevel(from level: OSLogEntryLog.Level) -> DiagnosticLogLevel {
        switch level {
        case .debug:
            .debug
        case .info:
            .info
        case .notice:
            .info
        case .error, .fault:
            .error
        case .undefined:
            .debug
        @unknown default:
            .info
        }
    }
}

/// 诊断日志纯文本格式化器，保持稳定输出便于测试和人工排查。
public enum DiagnosticLogFormatter {
    public static func format(
        records: [DiagnosticLogRecord],
        generatedAt: Date,
        since: Date,
        subsystemPrefixes: [String]
    ) -> String {
        var lines = [
            "HostCat Diagnostic Logs",
            "generatedAt: \(formatDate(generatedAt))",
            "since: \(formatDate(since))",
            "subsystems: \(subsystemPrefixes.joined(separator: ", "))",
            "levels: \(DiagnosticLogLevel.allCases.map(\.rawValue).joined(separator: ", "))",
            "records: \(records.count)",
            ""
        ]

        if records.isEmpty {
            lines.append("No HostCat log entries were found for the selected time range.")
        } else {
            lines.append(contentsOf: records.map(formatRecord))
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func formatRecord(_ record: DiagnosticLogRecord) -> String {
        let category = record.category.isEmpty ? "-" : record.category
        let process = record.process.isEmpty ? "-" : record.process
        let message = record.message.replacingOccurrences(of: "\n", with: "\n    ")
        return "\(formatDate(record.date)) [\(record.level.rawValue)] \(record.subsystem)/\(category) (\(process)) \(message)"
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
