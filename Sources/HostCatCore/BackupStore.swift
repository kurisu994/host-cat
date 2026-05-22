import Foundation
import os.log

/// 备份操作错误类型
public enum BackupStoreError: Error, Equatable, LocalizedError, Sendable {
    case directoryCreationFailed
    case writeFailed
    case cleanupFailed

    public var errorDescription: String? {
        switch self {
        case .directoryCreationFailed:
            "备份目录创建失败"
        case .writeFailed:
            "备份文件写入失败"
        case .cleanupFailed:
            "旧备份清理失败"
        }
    }
}

/// 备份存储管理器，负责保存、列出和读取 hosts 备份
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

    /// 创建一份新的备份，返回备份文件 URL
    public func createBackup(content: String) throws -> URL {
        do {
            try FileManager.default.createDirectory(
                at: backupDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            logger.error("备份目录创建失败: \(error.localizedDescription)")
            throw BackupStoreError.directoryCreationFailed
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let now = Date()
        let timestamp = formatter.string(from: now)

        // 使用 gettimeofday 获取微秒级精度，避免 Double 精度损失和 Y2038 后溢出风险
        var tv = timeval()
        gettimeofday(&tv, nil)
        let orderingToken = UInt64(tv.tv_sec) * 1_000_000_000 + UInt64(tv.tv_usec) * 1_000
        let paddedOrderingToken = String(format: "%020llu", orderingToken)
        let uniqueSuffix = UUID().uuidString.prefix(8)
        let filename = "\(Self.backupFilePrefix)\(timestamp)_\(paddedOrderingToken)_\(uniqueSuffix).\(Self.backupFileExtension)"
        let fileURL = backupDirectory.appendingPathComponent(filename)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            logger.info("备份创建成功: \(filename)")
        } catch {
            logger.error("备份写入失败: \(error.localizedDescription)")
            throw BackupStoreError.writeFailed
        }

        // 清理超出保留数量的旧备份
        do {
            try cleanupOldBackups()
        } catch {
            logger.warning("旧备份清理失败: \(error.localizedDescription)")
            // 不抛出 cleanup 错误，备份已创建成功
        }

        return fileURL
    }

    /// 列出所有备份文件，按时间倒序（最新的在前）
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

    /// 读取指定备份文件的内容
    public func readBackup(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return HostsImporter().importHostsWithFallback(data: data).decodedContent
    }

    /// 从文件名中提取日期（用于测试和展示）
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
                logger.debug("清理旧备份: \(url.lastPathComponent)")
            } catch {
                logger.error("删除旧备份失败 \(url.lastPathComponent): \(error.localizedDescription)")
                throw BackupStoreError.cleanupFailed
            }
        }
    }
}
