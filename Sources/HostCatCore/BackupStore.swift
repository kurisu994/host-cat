import Foundation
import os.log

/// Error type for backup operations.
public enum BackupStoreError: Error, Equatable, LocalizedError, Sendable {
    case directoryCreationFailed
    case writeFailed
    case cleanupFailed

    public var errorDescription: String? {
        switch self {
        case .directoryCreationFailed:
            LC.backupErrorDirectoryCreationFailed
        case .writeFailed:
            LC.backupErrorWriteFailed
        case .cleanupFailed:
            LC.backupErrorCleanupFailed
        }
    }
}

/// Manages backup storage: saving, listing, and reading hosts backups.
public struct BackupStore: Sendable {
    public static let backupFilePrefix = "hosts_"
    public static let backupFileExtension = "bak"
    public static let defaultMaxBackups = 20

    public var backupDirectory: URL
    public var maxBackups: Int
    private let logger = Logger(subsystem: "com.hostcat.app", category: "BackupStore")

    public init(
        backupDirectory: URL = Self.defaultBackupDirectory(),
        maxBackups: Int = Self.defaultMaxBackups
    ) {
        self.backupDirectory = backupDirectory
        self.maxBackups = max(0, maxBackups)
    }

    public static func defaultBackupDirectory() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.hostcat.app", isDirectory: true)
            .appendingPathComponent("backups", isDirectory: true)
    }

    /// Creates a new backup and returns the backup file URL.
    public func createBackup(content: String) throws -> URL {
        do {
            try FileManager.default.createDirectory(
                at: backupDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            logger.error("\(LC.logBackupFailed(error.localizedDescription), privacy: .public)")
            throw BackupStoreError.directoryCreationFailed
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let now = Date()
        let timestamp = formatter.string(from: now)

        // Use gettimeofday for microsecond precision, avoiding Double precision loss and Y2038 overflow risk.
        var tv = timeval()
        gettimeofday(&tv, nil)
        let orderingToken = UInt64(tv.tv_sec) * 1_000_000_000 + UInt64(tv.tv_usec) * 1_000
        let paddedOrderingToken = String(format: "%020llu", orderingToken)
        let uniqueSuffix = UUID().uuidString.prefix(8)
        let filename = "\(Self.backupFilePrefix)\(timestamp)_\(paddedOrderingToken)_\(uniqueSuffix).\(Self.backupFileExtension)"
        let fileURL = backupDirectory.appendingPathComponent(filename)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            logger.info("\(LC.logBackupCreated(filename), privacy: .public)")
        } catch {
            logger.error("\(LC.logBackupFailed(error.localizedDescription), privacy: .public)")
            throw BackupStoreError.writeFailed
        }

        // Clean up old backups that exceed the retention limit.
        do {
            try cleanupOldBackups()
        } catch {
            logger.warning("\(LC.logBackupFailed(error.localizedDescription), privacy: .public)")
            // Do not throw cleanup errors; the backup was created successfully.
        }

        return fileURL
    }

    /// Lists all backup files in reverse chronological order (newest first).
    ///
    /// 文件名里的日期是本地时间，跨时区或夏令时回拨后会倒退，不能直接按文件名排序；
    /// 这里按与时区无关的 ordering token（纪元纳秒）排序。
    public func listBackups() -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        let backupFiles = files.filter {
            $0.lastPathComponent.hasPrefix(Self.backupFilePrefix) && $0.pathExtension == Self.backupFileExtension
        }

        return backupFiles.sorted { lhs, rhs in
            let lhsToken = Self.orderingToken(from: lhs) ?? 0
            let rhsToken = Self.orderingToken(from: rhs) ?? 0
            if lhsToken != rhsToken {
                return lhsToken > rhsToken
            }
            return lhs.lastPathComponent > rhs.lastPathComponent
        }
    }

    /// Reads the content of the specified backup file.
    public func readBackup(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return HostsImporter().importHostsWithFallback(data: data).decodedContent
    }

    /// Extracts the date from a backup filename (used for testing and display).
    /// 优先用 ordering token 还原真实时间；没有 token 的旧文件名才回退到本地时间串。
    public static func extractDate(from url: URL) -> Date? {
        if let token = orderingToken(from: url) {
            return Date(timeIntervalSince1970: TimeInterval(token) / 1_000_000_000)
        }

        guard let body = filenameBody(of: url) else {
            return nil
        }
        let dateString = String(body.prefix("yyyy-MM-dd_HHmmss".count))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateString)
    }

    // MARK: - Private

    /// 文件名格式：`hosts_<yyyy-MM-dd>_<HHmmss>_<20 位纪元纳秒>_<随机后缀>.bak`，取出纪元纳秒。
    private static func orderingToken(from url: URL) -> UInt64? {
        guard let body = filenameBody(of: url) else {
            return nil
        }
        let parts = body.split(separator: "_")
        guard parts.count >= 3, parts[2].count == 20 else {
            return nil
        }
        return UInt64(parts[2])
    }

    /// 去掉前缀和扩展名后的文件名主体；不是备份文件时返回 nil。
    private static func filenameBody(of url: URL) -> String? {
        let filename = url.lastPathComponent
        let suffix = ".\(backupFileExtension)"
        guard filename.hasPrefix(backupFilePrefix), filename.hasSuffix(suffix) else {
            return nil
        }
        return String(filename.dropFirst(backupFilePrefix.count).dropLast(suffix.count))
    }

    private func cleanupOldBackups() throws {
        let backups = listBackups()
        guard backups.count > maxBackups, maxBackups > 0 else { return }

        let toRemove = backups.suffix(backups.count - maxBackups)
        for url in toRemove {
            do {
                try FileManager.default.removeItem(at: url)
                logger.debug("\(LC.logBackupCleaned(url.lastPathComponent), privacy: .public)")
            } catch {
                logger.error("\(LC.logBackupCleanFailed(url.lastPathComponent), privacy: .public): \(error.localizedDescription, privacy: .public)")
                throw BackupStoreError.cleanupFailed
            }
        }
    }
}
