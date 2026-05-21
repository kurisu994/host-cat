import Foundation
import Testing
@testable import HostCatCore

// MARK: - Fake 文件系统操作

/// 可配置的 Fake 文件系统操作，用于单元测试
struct FakeFileSystemOperations: FileSystemOperations, Sendable {
    var fileContents: [String: Data] = [:]
    var fileFlags: [String: UInt32] = [:]
    var realPaths: [String: String] = [:]
    var shouldFailMkstemp = false
    var shouldFailWrite = false
    var shouldFailFsync = false
    var shouldFailChmod = false
    var shouldFailChown = false
    var shouldFailRename = false
    var lastWrittenData: Data?
    var lastTempPath: String?
    var lastRenamedTo: String?
    var removedFiles: [String] = []

    // 用 class 包装可变状态，让 struct 满足 Sendable
    private let state = FakeState()

    final class FakeState: @unchecked Sendable {
        var writtenData: Data?
        var tempPath: String?
        var renamedFrom: String?
        var renamedTo: String?
        var removedFiles: [String] = []
        var permissionsSet: [(path: String, mode: mode_t)] = []
        var ownerSet: [(path: String, uid: uid_t, gid: gid_t)] = []
    }

    var writtenData: Data? { state.writtenData }
    var renamedTo: String? { state.renamedTo }
    var permissionsHistory: [(path: String, mode: mode_t)] { state.permissionsSet }
    var ownerHistory: [(path: String, uid: uid_t, gid: gid_t)] { state.ownerSet }

    func readFile(at path: String) throws -> Data {
        guard let data = fileContents[path] else {
            throw HostsWriteError.writeFailed("文件不存在: \(path)")
        }
        return data
    }

    func createTempFile(in directory: String, template: String) throws -> (fd: Int32, path: String) {
        if shouldFailMkstemp {
            throw HostsWriteError.tempFileCreationFailed("模拟 mkstemp 失败")
        }
        let path = "\(directory)/\(template).fake"
        state.tempPath = path
        return (42, path) // 返回假 fd
    }

    func writeData(_ data: Data, toFileDescriptor _: Int32) throws {
        if shouldFailWrite {
            throw HostsWriteError.writeFailed("模拟写入失败")
        }
        state.writtenData = data
    }

    func fsyncFD(_: Int32) throws {
        if shouldFailFsync {
            throw HostsWriteError.writeFailed("模拟 fsync 失败")
        }
    }

    func closeFD(_: Int32) {}

    func setPermissions(at path: String, mode: mode_t) throws {
        if shouldFailChmod {
            throw HostsWriteError.permissionSetFailed("模拟 chmod 失败")
        }
        state.permissionsSet.append((path, mode))
    }

    func setOwner(at path: String, uid: uid_t, gid: gid_t) throws {
        if shouldFailChown {
            throw HostsWriteError.permissionSetFailed("模拟 chown 失败")
        }
        state.ownerSet.append((path, uid, gid))
    }

    func rename(from oldPath: String, to newPath: String) throws {
        if shouldFailRename {
            throw HostsWriteError.renameFailed("模拟 rename 失败")
        }
        state.renamedFrom = oldPath
        state.renamedTo = newPath
    }

    func fsyncDirectory(at _: String) throws {}

    func removeFile(at path: String) throws {
        state.removedFiles.append(path)
    }

    func fileFlags(at path: String) throws -> UInt32 {
        fileFlags[path] ?? 0
    }

    func resolveRealPath(at path: String) throws -> String {
        realPaths[path] ?? path
    }
}

// MARK: - 测试用 hosts 内容

private let validHostsContent = """
# --- HostCat Begin (v1) ---

# ==============================
# 默认
127.0.0.1 localhost
::1 localhost

# --- HostCat End ---

"""

private let existingHostsContent = """
127.0.0.1 localhost
255.255.255.255 broadcasthost
::1 localhost
"""

// MARK: - Tests

@Suite("HostsFileWriter 安全写入测试")
struct HostsFileWriterTests {
    let writer = HostsFileWriter()
    let targetPath = "/private/etc/hosts"

    // MARK: - Immutable Flags

    @Test("immutable flags 阻止写入")
    func immutableFlagsBlockWrite() throws {
        var ops = FakeFileSystemOperations()
        ops.fileFlags[targetPath] = UInt32(UF_IMMUTABLE)
        ops.fileContents[targetPath] = Data(existingHostsContent.utf8)

        #expect(throws: HostsWriteError.fileImmutable) {
            _ = try writer.write(
                content: validHostsContent,
                targetPath: targetPath,
                expectedHash: nil,
                fileOps: ops
            )
        }
    }

    @Test("SF_IMMUTABLE（系统 immutable）同样阻止写入")
    func systemImmutableFlagsBlockWrite() throws {
        var ops = FakeFileSystemOperations()
        ops.fileFlags[targetPath] = UInt32(SF_IMMUTABLE)
        ops.fileContents[targetPath] = Data(existingHostsContent.utf8)

        #expect(throws: HostsWriteError.fileImmutable) {
            _ = try writer.write(
                content: validHostsContent,
                targetPath: targetPath,
                expectedHash: nil,
                fileOps: ops
            )
        }
    }

    @Test("无 immutable flags 时正常继续")
    func noImmutableFlagsAllowWrite() throws {
        var ops = FakeFileSystemOperations()
        ops.fileFlags[targetPath] = 0
        ops.fileContents[targetPath] = Data(existingHostsContent.utf8)

        let outcome = try writer.write(
            content: validHostsContent,
            targetPath: targetPath,
            expectedHash: nil,
            fileOps: ops
        )
        #expect(outcome.finalHash == HostsHash.sha256Hex(validHostsContent))
    }

    // MARK: - Hash 校验

    @Test("hash 不匹配时阻止写入")
    func hashMismatchBlocksWrite() throws {
        var ops = FakeFileSystemOperations()
        ops.fileContents[targetPath] = Data(existingHostsContent.utf8)

        #expect(throws: HostsWriteError.hashMismatch) {
            _ = try writer.write(
                content: validHostsContent,
                targetPath: targetPath,
                expectedHash: "wrong-hash-value",
                fileOps: ops
            )
        }
    }

    @Test("hash 匹配时允许写入")
    func hashMatchAllowsWrite() throws {
        var ops = FakeFileSystemOperations()
        ops.fileContents[targetPath] = Data(existingHostsContent.utf8)
        let correctHash = HostsHash.sha256Hex(existingHostsContent)

        let outcome = try writer.write(
            content: validHostsContent,
            targetPath: targetPath,
            expectedHash: correctHash,
            fileOps: ops
        )
        #expect(outcome.finalHash == HostsHash.sha256Hex(validHostsContent))
    }

    @Test("expectedHash 为 nil 时跳过校验")
    func nilHashSkipsCheck() throws {
        var ops = FakeFileSystemOperations()
        ops.fileContents[targetPath] = Data(existingHostsContent.utf8)

        let outcome = try writer.write(
            content: validHostsContent,
            targetPath: targetPath,
            expectedHash: nil,
            fileOps: ops
        )
        #expect(outcome.finalHash == HostsHash.sha256Hex(validHostsContent))
    }

    @Test("expectedHash 为空字符串时跳过校验")
    func emptyHashSkipsCheck() throws {
        var ops = FakeFileSystemOperations()
        ops.fileContents[targetPath] = Data(existingHostsContent.utf8)

        let outcome = try writer.write(
            content: validHostsContent,
            targetPath: targetPath,
            expectedHash: "",
            fileOps: ops
        )
        #expect(outcome.finalHash == HostsHash.sha256Hex(validHostsContent))
    }

    // MARK: - 内容校验

    @Test("空内容阻止写入")
    func emptyContentBlocksWrite() throws {
        var ops = FakeFileSystemOperations()
        ops.fileContents[targetPath] = Data(existingHostsContent.utf8)

        #expect {
            _ = try writer.write(
                content: "",
                targetPath: targetPath,
                expectedHash: nil,
                fileOps: ops
            )
        } throws: { error in
            if case HostsWriteError.contentValidationFailed = error {
                return true
            }
            return false
        }
    }

    @Test("缺少 Begin 标记阻止写入")
    func missingBeginMarkerBlocksWrite() throws {
        var ops = FakeFileSystemOperations()
        ops.fileContents[targetPath] = Data(existingHostsContent.utf8)
        let noBegin = "127.0.0.1 localhost\n# --- HostCat End ---\n"

        #expect {
            _ = try writer.write(
                content: noBegin,
                targetPath: targetPath,
                expectedHash: nil,
                fileOps: ops
            )
        } throws: { error in
            if case HostsWriteError.contentValidationFailed = error {
                return true
            }
            return false
        }
    }

    @Test("缺少 End 标记阻止写入")
    func missingEndMarkerBlocksWrite() throws {
        var ops = FakeFileSystemOperations()
        ops.fileContents[targetPath] = Data(existingHostsContent.utf8)
        let noEnd = "# --- HostCat Begin (v1) ---\n127.0.0.1 localhost\n"

        #expect {
            _ = try writer.write(
                content: noEnd,
                targetPath: targetPath,
                expectedHash: nil,
                fileOps: ops
            )
        } throws: { error in
            if case HostsWriteError.contentValidationFailed = error {
                return true
            }
            return false
        }
    }

    // MARK: - 写入流程错误

    @Test("mkstemp 失败时抛出 tempFileCreationFailed")
    func mkstempFailure() throws {
        var ops = FakeFileSystemOperations()
        ops.fileContents[targetPath] = Data(existingHostsContent.utf8)
        ops.shouldFailMkstemp = true

        #expect {
            _ = try writer.write(
                content: validHostsContent,
                targetPath: targetPath,
                expectedHash: nil,
                fileOps: ops
            )
        } throws: { error in
            if case HostsWriteError.tempFileCreationFailed = error {
                return true
            }
            return false
        }
    }

    @Test("写入临时文件失败")
    func writeToTempFileFailure() throws {
        var ops = FakeFileSystemOperations()
        ops.fileContents[targetPath] = Data(existingHostsContent.utf8)
        ops.shouldFailWrite = true

        #expect {
            _ = try writer.write(
                content: validHostsContent,
                targetPath: targetPath,
                expectedHash: nil,
                fileOps: ops
            )
        } throws: { error in
            if case HostsWriteError.writeFailed = error {
                return true
            }
            return false
        }
    }

    @Test("chmod 失败时抛出 permissionSetFailed")
    func chmodFailure() throws {
        var ops = FakeFileSystemOperations()
        ops.fileContents[targetPath] = Data(existingHostsContent.utf8)
        ops.shouldFailChmod = true

        #expect {
            _ = try writer.write(
                content: validHostsContent,
                targetPath: targetPath,
                expectedHash: nil,
                fileOps: ops
            )
        } throws: { error in
            if case HostsWriteError.permissionSetFailed = error {
                return true
            }
            return false
        }
    }

    @Test("chown 失败时抛出 permissionSetFailed")
    func chownFailure() throws {
        var ops = FakeFileSystemOperations()
        ops.fileContents[targetPath] = Data(existingHostsContent.utf8)
        ops.shouldFailChown = true

        #expect {
            _ = try writer.write(
                content: validHostsContent,
                targetPath: targetPath,
                expectedHash: nil,
                fileOps: ops
            )
        } throws: { error in
            if case HostsWriteError.permissionSetFailed = error {
                return true
            }
            return false
        }
    }

    @Test("rename 失败时抛出 renameFailed")
    func renameFailure() throws {
        var ops = FakeFileSystemOperations()
        ops.fileContents[targetPath] = Data(existingHostsContent.utf8)
        ops.shouldFailRename = true

        #expect {
            _ = try writer.write(
                content: validHostsContent,
                targetPath: targetPath,
                expectedHash: nil,
                fileOps: ops
            )
        } throws: { error in
            if case HostsWriteError.renameFailed = error {
                return true
            }
            return false
        }
    }

    // MARK: - 正常写入

    @Test("正常写入成功：权限设置为 644、属主设置为 root:wheel")
    func successfulWrite() throws {
        var ops = FakeFileSystemOperations()
        ops.fileContents[targetPath] = Data(existingHostsContent.utf8)

        let outcome = try writer.write(
            content: validHostsContent,
            targetPath: targetPath,
            expectedHash: nil,
            fileOps: ops
        )

        #expect(outcome.finalHash == HostsHash.sha256Hex(validHostsContent))
        #expect(outcome.dnsRefreshSuccess == true)

        // 验证写入了正确的数据
        #expect(ops.writtenData == Data(validHostsContent.utf8))

        // 验证权限设置
        #expect(ops.permissionsHistory.count == 1)
        #expect(ops.permissionsHistory[0].mode == 0o644)

        // 验证属主设置
        #expect(ops.ownerHistory.count == 1)
        #expect(ops.ownerHistory[0].uid == 0)
        #expect(ops.ownerHistory[0].gid == 0)
    }

    // MARK: - DNS 刷新

    @Test("DNS 刷新失败不影响写入结果")
    func dnsRefreshFailureDoesNotAffectWrite() throws {
        var ops = FakeFileSystemOperations()
        ops.fileContents[targetPath] = Data(existingHostsContent.utf8)
        let failingDNS = StubDNSRefresher(shouldSucceed: false, errorMessage: "DNS 超时")

        let outcome = try writer.write(
            content: validHostsContent,
            targetPath: targetPath,
            expectedHash: nil,
            fileOps: ops,
            dnsRefresher: failingDNS
        )

        // 写入成功但 DNS 刷新失败
        #expect(outcome.finalHash == HostsHash.sha256Hex(validHostsContent))
        #expect(outcome.dnsRefreshSuccess == false)
        #expect(outcome.dnsRefreshError != nil)
    }

    @Test("DNS 刷新成功时结果正确")
    func dnsRefreshSuccess() throws {
        var ops = FakeFileSystemOperations()
        ops.fileContents[targetPath] = Data(existingHostsContent.utf8)
        let successDNS = StubDNSRefresher(shouldSucceed: true)

        let outcome = try writer.write(
            content: validHostsContent,
            targetPath: targetPath,
            expectedHash: nil,
            fileOps: ops,
            dnsRefresher: successDNS
        )

        #expect(outcome.dnsRefreshSuccess == true)
        #expect(outcome.dnsRefreshError == nil)
    }

    @Test("不传 DNS 刷新器时跳过刷新")
    func noDNSRefresherSkipsRefresh() throws {
        var ops = FakeFileSystemOperations()
        ops.fileContents[targetPath] = Data(existingHostsContent.utf8)

        let outcome = try writer.write(
            content: validHostsContent,
            targetPath: targetPath,
            expectedHash: nil,
            fileOps: ops,
            dnsRefresher: nil
        )

        #expect(outcome.dnsRefreshSuccess == true)
    }
}
