import Foundation
import os.log

// MARK: - 文件系统操作协议

/// 文件系统操作协议，通过协议注入实现可测试性。
/// Helper 使用真实实现，测试使用 Fake 实现。
public protocol FileSystemOperations: Sendable {
    /// 读取文件内容
    func readFile(at path: String) throws -> Data
    /// 通过 mkstemp 在指定目录创建唯一临时文件
    func createTempFile(in directory: String, template: String) throws -> (fd: Int32, path: String)
    /// 向文件描述符写入数据
    func writeData(_ data: Data, toFileDescriptor fd: Int32) throws
    /// 同步文件描述符
    func fsyncFD(_ fd: Int32) throws
    /// 关闭文件描述符
    func closeFD(_ fd: Int32)
    /// 设置文件权限
    func setPermissions(at path: String, mode: mode_t) throws
    /// 设置文件属主和属组
    func setOwner(at path: String, uid: uid_t, gid: gid_t) throws
    /// 原子重命名
    func rename(from oldPath: String, to newPath: String) throws
    /// 同步目录（降低断电导致目录项未落盘的风险）
    func fsyncDirectory(at path: String) throws
    /// 删除文件
    func removeFile(at path: String) throws
    /// 检查文件的 immutable flags（schg / uchg）
    func fileFlags(at path: String) throws -> UInt32
    /// 解析真实路径（跟踪符号链接）
    func resolveRealPath(at path: String) throws -> String
}

// MARK: - 真实文件系统实现

/// 基于 POSIX API 的真实文件系统操作
public struct RealFileSystemOperations: FileSystemOperations, Sendable {
    public init() {}

    public func readFile(at path: String) throws -> Data {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw HostsWriteError.writeFailed("无法读取文件 \(path)")
        }
        return data
    }

    public func createTempFile(in directory: String, template: String) throws -> (fd: Int32, path: String) {
        let fullTemplate = (directory as NSString).appendingPathComponent(template)
        var templateBytes = Array(fullTemplate.utf8CString)
        let fd = mkstemp(&templateBytes)
        guard fd >= 0 else {
            throw HostsWriteError.tempFileCreationFailed(String(cString: strerror(errno)))
        }
        let path = templateBytes.withUnsafeBufferPointer { buffer in
            String(decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8($0) }, as: UTF8.self)
        }
        return (fd, path)
    }

    public func writeData(_ data: Data, toFileDescriptor fd: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var remaining = data.count
            var offset = 0
            while remaining > 0 {
                let written = Darwin.write(fd, base.advanced(by: offset), remaining)
                guard written > 0 else {
                    throw HostsWriteError.writeFailed("write() 失败：\(String(cString: strerror(errno)))")
                }
                offset += written
                remaining -= written
            }
        }
    }

    public func fsyncFD(_ fd: Int32) throws {
        guard Darwin.fsync(fd) == 0 else {
            throw HostsWriteError.writeFailed("fsync 失败：\(String(cString: strerror(errno)))")
        }
    }

    public func closeFD(_ fd: Int32) {
        Darwin.close(fd)
    }

    public func setPermissions(at path: String, mode: mode_t) throws {
        guard chmod(path, mode) == 0 else {
            throw HostsWriteError.permissionSetFailed("chmod \(String(mode, radix: 8)) 失败：\(String(cString: strerror(errno)))")
        }
    }

    public func setOwner(at path: String, uid: uid_t, gid: gid_t) throws {
        guard chown(path, uid, gid) == 0 else {
            throw HostsWriteError.permissionSetFailed("chown \(uid):\(gid) 失败：\(String(cString: strerror(errno)))")
        }
    }

    public func rename(from oldPath: String, to newPath: String) throws {
        guard Darwin.rename(oldPath, newPath) == 0 else {
            throw HostsWriteError.renameFailed("rename 失败：\(String(cString: strerror(errno)))")
        }
    }

    public func fsyncDirectory(at path: String) throws {
        let fd = Darwin.open(path, O_RDONLY)
        guard fd >= 0 else { return } // 目录 fsync 失败不阻止后续
        Darwin.fsync(fd)
        Darwin.close(fd)
    }

    public func removeFile(at path: String) throws {
        guard Darwin.unlink(path) == 0 || errno == ENOENT else {
            throw HostsWriteError.writeFailed("删除临时文件失败：\(String(cString: strerror(errno)))")
        }
    }

    public func fileFlags(at path: String) throws -> UInt32 {
        var sb = Darwin.stat()
        guard lstat(path, &sb) == 0 else {
            throw HostsWriteError.writeFailed("stat 失败：\(String(cString: strerror(errno)))")
        }
        return sb.st_flags
    }

    public func resolveRealPath(at path: String) throws -> String {
        guard let resolved = Darwin.realpath(path, nil) else {
            throw HostsWriteError.writeFailed("realpath 失败：\(String(cString: strerror(errno)))")
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}

// MARK: - 写入结果

/// hosts 写入结果
public struct HostsWriteOutcome: Equatable, Sendable {
    /// 写入后 hosts 文件的 SHA256 hash
    public var finalHash: String
    /// DNS 刷新是否成功
    public var dnsRefreshSuccess: Bool
    /// DNS 刷新失败的原因（仅当 dnsRefreshSuccess = false 时有值）
    public var dnsRefreshError: String?

    public init(finalHash: String, dnsRefreshSuccess: Bool, dnsRefreshError: String? = nil) {
        self.finalHash = finalHash
        self.dnsRefreshSuccess = dnsRefreshSuccess
        self.dnsRefreshError = dnsRefreshError
    }
}

// MARK: - 内容校验器

/// hosts 内容写入前校验
public struct HostsContentValidator: Sendable {
    public init() {}

    /// 校验即将写入的 hosts 内容是否完整有效
    public func validate(_ content: String) throws {
        // 1. 非空
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HostsWriteError.contentValidationFailed("内容为空")
        }

        // 2. 包含 HostCat 管理区块标记
        guard content.contains(HostsImporter.beginMarkerPrefix) else {
            throw HostsWriteError.contentValidationFailed("缺少 HostCat Begin 标记")
        }
        guard content.contains(HostsImporter.endMarker) else {
            throw HostsWriteError.contentValidationFailed("缺少 HostCat End 标记")
        }
    }
}

// MARK: - HostsFileWriter

/// hosts 文件写入器
///
/// 实现设计文档中的安全写入策略：
/// 1. 检查 immutable flags
/// 2. hash 校验防止覆盖外部修改
/// 3. mkstemp + fsync + chmod/chown + rename 原子替换
/// 4. 可选 DNS 刷新
public struct HostsFileWriter: Sendable {
    private let logger = Logger(subsystem: "com.hostcat.helper", category: "HostsFileWriter")

    public init() {}

    /// 执行安全写入
    ///
    /// - Parameters:
    ///   - content: 要写入的 hosts 文本
    ///   - targetPath: 目标路径（已通过 realpath 解析）
    ///   - expectedHash: 预期的当前 hosts hash，nil 表示跳过检查
    ///   - fileOps: 文件系统操作注入
    ///   - dnsRefresher: DNS 刷新器注入，nil 表示跳过刷新
    /// - Returns: 写入结果
    public func write(
        content: String,
        targetPath: String,
        expectedHash: String?,
        fileOps: FileSystemOperations,
        contentValidator: HostsContentValidator = HostsContentValidator(),
        dnsRefresher: DNSRefreshing? = nil
    ) throws -> HostsWriteOutcome {
        let directory = (targetPath as NSString).deletingLastPathComponent
        var tempPath: String?

        defer {
            // 无论成功或失败，尝试清理临时文件
            if let temp = tempPath {
                do {
                    try fileOps.removeFile(at: temp)
                } catch {
                    logger.warning("清理临时文件失败: \(error.localizedDescription)")
                }
            }
        }

        // 1. 检查 immutable flags（schg / uchg）
        let flags = try fileOps.fileFlags(at: targetPath)
        let immutableMask: UInt32 = UInt32(UF_IMMUTABLE) | UInt32(SF_IMMUTABLE)
        if flags & immutableMask != 0 {
            logger.error("hosts 文件设置了 immutable flags: \(flags)")
            throw HostsWriteError.fileImmutable
        }

        // 2. 读取当前 hosts 并校验 hash
        let currentData = try fileOps.readFile(at: targetPath)
        let currentContent = String(data: currentData, encoding: .utf8) ?? String(data: currentData, encoding: .isoLatin1) ?? ""
        let currentHash = HostsHash.sha256Hex(currentContent)

        if let expectedHash, !expectedHash.isEmpty, currentHash != expectedHash {
            logger.warning("hash 不匹配: expected=\(expectedHash.prefix(8))..., current=\(currentHash.prefix(8))...")
            throw HostsWriteError.hashMismatch
        }

        // 3. 校验写入内容
        try contentValidator.validate(content)

        // 4. mkstemp 创建临时文件
        let (fd, createdTempPath) = try fileOps.createTempFile(in: directory, template: ".hosts.hostcat.XXXXXX")
        tempPath = createdTempPath
        logger.debug("创建临时文件: \(createdTempPath)")

        // 5. 写入内容 + fsync
        let contentData = Data(content.utf8)
        do {
            try fileOps.writeData(contentData, toFileDescriptor: fd)
            try fileOps.fsyncFD(fd)
        } catch {
            fileOps.closeFD(fd)
            throw error
        }
        fileOps.closeFD(fd)

        // 6. 设置权限：chmod 644 + chown root:wheel
        try fileOps.setPermissions(at: createdTempPath, mode: 0o644)
        try fileOps.setOwner(at: createdTempPath, uid: 0, gid: 0) // root:wheel

        // 7. rename(2) 原子替换
        try fileOps.rename(from: createdTempPath, to: targetPath)
        tempPath = nil // rename 成功后不需要清理

        // 8. fsync 父目录
        try fileOps.fsyncDirectory(at: directory)

        // 计算最终 hash
        let finalHash = HostsHash.sha256Hex(content)

        logger.info("写入成功, hash: \(finalHash.prefix(8))...")

        // 9. DNS 缓存刷新
        var dnsSuccess = true
        var dnsError: String?
        if let refresher = dnsRefresher {
            do {
                try refresher.refreshDNSCache()
                logger.info("DNS 缓存刷新成功")
            } catch {
                dnsSuccess = false
                dnsError = error.localizedDescription
                logger.warning("DNS 缓存刷新失败: \(error.localizedDescription)")
                // DNS 刷新失败不回滚 hosts，但记录错误
            }
        }

        return HostsWriteOutcome(
            finalHash: finalHash,
            dnsRefreshSuccess: dnsSuccess,
            dnsRefreshError: dnsError
        )
    }
}
