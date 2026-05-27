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
    public static let defaultMaxBackups = 3

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
            logger.error("\(LC.logBackupFailed(error.localizedDescription))")
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
            logger.info("\(LC.logBackupCreated(filename))")
        } catch {
            logger.error("\(LC.logBackupFailed(error.localizedDescription))")
            throw BackupStoreError.writeFailed
        }

        // Clean up old backups that exceed the retention limit.
        do {
            try cleanupOldBackups()
        } catch {
            logger.warning("\(LC.logBackupFailed(error.localizedDescription))")
            // Do not throw cleanup errors; the backup was created successfully.
        }

        return fileURL
    }

    /// Lists all backup files in reverse chronological order (newest first).
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

        return backupFiles.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Reads the content of the specified backup file.
    public func readBackup(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return HostsImporter().importHostsWithFallback(data: data).decodedContent
    }

    /// Extracts the date from a backup filename (used for testing and display).
    public static func extractDate(from url: URL) -> Date? {
        let filename = url.lastPathComponent
        let prefix = Self.backupFilePrefix
        let suffix = ".\(Self.backupFileExtension)"
        guard filename.hasPrefix(prefix), filename.hasSuffix(suffix) else {
            return nil
        }

        let body = String(filename.dropFirst(prefix.count).dropLast(suffix.count))
        let dateString = String(body.prefix("yyyy-MM-dd_HHmmss".count))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateString)
    }

    // MARK: - Private

    private func cleanupOldBackups() throws {
        let backups = listBackups()
        guard backups.count > maxBackups, maxBackups > 0 else { return }

        let toRemove = backups.suffix(backups.count - maxBackups)
        for url in toRemove {
            do {
                try FileManager.default.removeItem(at: url)
                logger.debug("\(LC.logBackupCleaned(url.lastPathComponent))")
            } catch {
                logger.error("\(LC.logBackupCleanFailed(url.lastPathComponent)): \(error.localizedDescription)")
                throw BackupStoreError.cleanupFailed
            }
        }
    }
}
