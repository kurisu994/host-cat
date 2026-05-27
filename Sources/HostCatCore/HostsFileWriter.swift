import Foundation
import os.log

// MARK: - File System Operations Protocol

/// File system operations protocol for dependency injection (testability).
/// The Helper uses the real implementation; tests use a fake.
public protocol FileSystemOperations: Sendable {
    /// Reads file contents.
    func readFile(at path: String) throws -> Data
    /// Creates a unique temporary file via mkstemp in the specified directory.
    func createTempFile(in directory: String, template: String) throws -> (fd: Int32, path: String)
    /// Writes data to a file descriptor.
    func writeData(_ data: Data, toFileDescriptor fd: Int32) throws
    /// Syncs a file descriptor.
    func fsyncFD(_ fd: Int32) throws
    /// Closes a file descriptor.
    func closeFD(_ fd: Int32)
    /// Sets file permissions.
    func setPermissions(at path: String, mode: mode_t) throws
    /// Sets file owner and group.
    func setOwner(at path: String, uid: uid_t, gid: gid_t) throws
    /// Atomically renames a file.
    func rename(from oldPath: String, to newPath: String) throws
    /// Syncs the directory (reduces risk of directory entry loss on power failure).
    func fsyncDirectory(at path: String) throws
    /// Removes a file.
    func removeFile(at path: String) throws
    /// Checks the file's immutable flags (schg / uchg).
    func fileFlags(at path: String) throws -> UInt32
    /// Resolves the real path (follows symlinks).
    func resolveRealPath(at path: String) throws -> String
}

// MARK: - Real File System Implementation

/// Real file system operations based on POSIX APIs.
public struct RealFileSystemOperations: FileSystemOperations, Sendable {
    public init() {}

    public func readFile(at path: String) throws -> Data {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw HostsWriteError.writeFailed("Failed to read file \(path)")
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
                    throw HostsWriteError.writeFailed("write() failed: \(String(cString: strerror(errno)))")
                }
                offset += written
                remaining -= written
            }
        }
    }

    public func fsyncFD(_ fd: Int32) throws {
        guard Darwin.fsync(fd) == 0 else {
            throw HostsWriteError.writeFailed("fsync failed: \(String(cString: strerror(errno)))")
        }
    }

    public func closeFD(_ fd: Int32) {
        Darwin.close(fd)
    }

    public func setPermissions(at path: String, mode: mode_t) throws {
        guard chmod(path, mode) == 0 else {
            throw HostsWriteError.permissionSetFailed("chmod \(String(mode, radix: 8)) failed: \(String(cString: strerror(errno)))")
        }
    }

    public func setOwner(at path: String, uid: uid_t, gid: gid_t) throws {
        guard chown(path, uid, gid) == 0 else {
            throw HostsWriteError.permissionSetFailed("chown \(uid):\(gid) failed: \(String(cString: strerror(errno)))")
        }
    }

    public func rename(from oldPath: String, to newPath: String) throws {
        guard Darwin.rename(oldPath, newPath) == 0 else {
            throw HostsWriteError.renameFailed("rename failed: \(String(cString: strerror(errno)))")
        }
    }

    public func fsyncDirectory(at path: String) throws {
        let fd = Darwin.open(path, O_RDONLY)
        guard fd >= 0 else { return } // Directory fsync failure is not blocking.
        Darwin.fsync(fd)
        Darwin.close(fd)
    }

    public func removeFile(at path: String) throws {
        guard Darwin.unlink(path) == 0 || errno == ENOENT else {
            throw HostsWriteError.writeFailed("Failed to remove temp file: \(String(cString: strerror(errno)))")
        }
    }

    public func fileFlags(at path: String) throws -> UInt32 {
        var sb = Darwin.stat()
        guard lstat(path, &sb) == 0 else {
            throw HostsWriteError.writeFailed("stat failed: \(String(cString: strerror(errno)))")
        }
        return sb.st_flags
    }

    public func resolveRealPath(at path: String) throws -> String {
        guard let resolved = Darwin.realpath(path, nil) else {
            throw HostsWriteError.writeFailed("realpath failed: \(String(cString: strerror(errno)))")
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}

// MARK: - Write Result

/// Result of a hosts file write operation.
public struct HostsWriteOutcome: Equatable, Sendable {
    /// SHA256 hash of the hosts file after writing.
    public var finalHash: String
    /// Whether DNS refresh succeeded.
    public var dnsRefreshSuccess: Bool
    /// Reason for DNS refresh failure (only set when dnsRefreshSuccess is false).
    public var dnsRefreshError: String?

    public init(finalHash: String, dnsRefreshSuccess: Bool, dnsRefreshError: String? = nil) {
        self.finalHash = finalHash
        self.dnsRefreshSuccess = dnsRefreshSuccess
        self.dnsRefreshError = dnsRefreshError
    }
}

// MARK: - Content Validator

/// Validates hosts content before writing.
public struct HostsContentValidator: Sendable {
    private static let requiredSystemEntries: [(ipAddress: String, hostname: String)] = [
        ("127.0.0.1", "localhost"),
        ("255.255.255.255", "broadcasthost"),
        ("::1", "localhost")
    ]

    public init() {}

    /// Validates that the hosts content to be written is complete and valid.
    public func validate(_ content: String) throws {
        // 1. Non-empty
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HostsWriteError.contentValidationFailed("Content is empty")
        }

        // 2. Contains HostCat management block markers
        guard content.contains(HostsImporter.beginMarkerPrefix) else {
            throw HostsWriteError.contentValidationFailed("Missing HostCat Begin marker")
        }
        guard content.contains(HostsImporter.endMarker) else {
            throw HostsWriteError.contentValidationFailed("Missing HostCat End marker")
        }

        let records: [HostRecord]
        do {
            records = try HostsParser().parse(content)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            throw HostsWriteError.contentValidationFailed(message)
        }

        for required in Self.requiredSystemEntries {
            let containsEntry = records.contains { record in
                record.ipAddress == required.ipAddress
                    && record.hostnames.contains { $0.lowercased() == required.hostname }
            }
            guard containsEntry else {
                throw HostsWriteError.contentValidationFailed(
                    "Missing required system entry \(required.ipAddress) \(required.hostname)"
                )
            }
        }
    }
}

// MARK: - HostsFileWriter

/// Hosts file writer.
///
/// Implements the safe write strategy from the design document:
/// 1. Check immutable flags
/// 2. Hash validation to prevent overwriting external changes
/// 3. Recheck the current hash immediately before atomic replacement
/// 4. mkstemp + fsync + chmod/chown + rename for atomic replacement
/// 5. Optional DNS refresh
public struct HostsFileWriter: Sendable {
    private let logger = Logger(subsystem: "com.hostcat.helper", category: "HostsFileWriter")

    public init() {}

    /// Performs a safe write.
    ///
    /// - Parameters:
    ///   - content: The hosts text to write.
    ///   - targetPath: The target path (already resolved via realpath).
    ///   - expectedHash: The expected current hosts hash; nil skips the check.
    ///   - fileOps: Injected file system operations.
    ///   - dnsRefresher: Injected DNS refresher; nil skips refresh.
    /// - Returns: The write result.
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
            // Clean up the temporary file on success or failure.
            if let temp = tempPath {
                do {
                    try fileOps.removeFile(at: temp)
                } catch {
                    logger.warning("Failed to clean up temp file: \(error.localizedDescription)")
                }
            }
        }

        // 1. Check immutable flags (schg / uchg)
        let flags = try fileOps.fileFlags(at: targetPath)
        let immutableMask: UInt32 = UInt32(UF_IMMUTABLE) | UInt32(SF_IMMUTABLE)
        if flags & immutableMask != 0 {
            logger.error("hosts file has immutable flags set: \(flags)")
            throw HostsWriteError.fileImmutable
        }

        // 2. Read current hosts and validate hash
        let currentData = try fileOps.readFile(at: targetPath)
        let currentContent = String(data: currentData, encoding: .utf8) ?? String(data: currentData, encoding: .isoLatin1) ?? ""
        let currentHash = HostsHash.sha256Hex(currentContent)

        if let expectedHash, !expectedHash.isEmpty, currentHash != expectedHash {
            logger.warning("hash mismatch: expected=\(expectedHash.prefix(8))..., current=\(currentHash.prefix(8))...")
            throw HostsWriteError.hashMismatch
        }

        // 3. Validate content to be written
        try contentValidator.validate(content)

        // 4. Create temp file via mkstemp
        let (fd, createdTempPath) = try fileOps.createTempFile(in: directory, template: ".hosts.hostcat.XXXXXX")
        tempPath = createdTempPath
        logger.debug("Created temp file: \(createdTempPath)")

        // 5. Write content + fsync
        let contentData = Data(content.utf8)
        do {
            try fileOps.writeData(contentData, toFileDescriptor: fd)
            try fileOps.fsyncFD(fd)
        } catch {
            fileOps.closeFD(fd)
            throw error
        }
        fileOps.closeFD(fd)

        // 6. Set permissions: chmod 644 + chown root:wheel
        try fileOps.setPermissions(at: createdTempPath, mode: 0o644)
        try fileOps.setOwner(at: createdTempPath, uid: 0, gid: 0) // root:wheel

        // 7. Refuse to replace a file modified while the temporary file was prepared.
        let latestData = try fileOps.readFile(at: targetPath)
        let latestContent = String(data: latestData, encoding: .utf8) ?? String(data: latestData, encoding: .isoLatin1) ?? ""
        let latestHash = HostsHash.sha256Hex(latestContent)
        if latestHash != currentHash {
            logger.warning("hash changed during write preparation: initial=\(currentHash.prefix(8))..., latest=\(latestHash.prefix(8))...")
            throw HostsWriteError.hashMismatch
        }

        // 8. rename(2) atomic replacement
        try fileOps.rename(from: createdTempPath, to: targetPath)
        tempPath = nil // No cleanup needed after successful rename.

        // 9. fsync parent directory
        try fileOps.fsyncDirectory(at: directory)

        // Compute final hash
        let finalHash = HostsHash.sha256Hex(content)

        logger.info("Write successful, hash: \(finalHash.prefix(8))...")

        // 10. DNS cache refresh
        var dnsSuccess = true
        var dnsError: String?
        if let refresher = dnsRefresher {
            do {
                try refresher.refreshDNSCache()
                logger.info("DNS cache refreshed successfully")
            } catch {
                dnsSuccess = false
                dnsError = error.localizedDescription
                logger.warning("DNS cache refresh failed: \(error.localizedDescription)")
                // DNS refresh failure does not roll back hosts, but the error is recorded.
            }
        }

        return HostsWriteOutcome(
            finalHash: finalHash,
            dnsRefreshSuccess: dnsSuccess,
            dnsRefreshError: dnsError
        )
    }
}
