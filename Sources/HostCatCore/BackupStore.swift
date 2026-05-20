import Foundation

/// 备份存储管理器，负责保存、列出和读取 hosts 备份
public struct BackupStore: Sendable {
    public var backupDirectory: URL
    public var maxBackups: Int

    public init(
        backupDirectory: URL = Self.defaultBackupDirectory(),
        maxBackups: Int = 3
    ) {
        self.backupDirectory = backupDirectory
        self.maxBackups = maxBackups
    }

    public static func defaultBackupDirectory() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.hostcat.app", isDirectory: true)
            .appendingPathComponent("backups", isDirectory: true)
    }

    /// 创建一份新的备份，返回备份文件 URL
    public func createBackup(content: String) -> URL? {
        do {
            try FileManager.default.createDirectory(
                at: backupDirectory,
                withIntermediateDirectories: true
            )

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HHmmss"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            let timestamp = formatter.string(from: Date())
            let filename = "hosts_\(timestamp).bak"
            let fileURL = backupDirectory.appendingPathComponent(filename)

            try content.write(to: fileURL, atomically: true, encoding: .utf8)

            // 清理超出保留数量的旧备份
            cleanupOldBackups()

            return fileURL
        } catch {
            return nil
        }
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

        let backupFiles = files.filter { $0.pathExtension == "bak" }

        return backupFiles.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
            return date1 > date2
        }
    }

    /// 读取指定备份文件的内容
    public func readBackup(at url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    /// 从文件名中提取日期（用于测试和展示）
    public static func extractDate(from url: URL) -> Date? {
        let filename = url.lastPathComponent
        let prefix = "hosts_"
        let suffix = ".bak"
        guard filename.hasPrefix(prefix), filename.hasSuffix(suffix) else {
            return nil
        }

        let dateString = String(filename.dropFirst(prefix.count).dropLast(suffix.count))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateString)
    }

    // MARK: - Private

    private func cleanupOldBackups() {
        let backups = listBackups()
        guard backups.count > maxBackups else { return }

        let toRemove = backups.suffix(backups.count - maxBackups)
        for url in toRemove {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
