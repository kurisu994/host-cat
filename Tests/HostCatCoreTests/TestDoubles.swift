import Foundation
@testable import HostCatCore

// MARK: - Fake Helper Client

/// 用于测试的 fake helper client
actor FakeHostHelperClient: HostHelperClient {
    var shouldSucceed: Bool = true
    var simulatedError: Error?
    var writtenContents: [String] = []
    var expectedHashes: [String?] = []
    var delayNanoseconds: UInt64 = 0

    func writeHosts(_ contents: String, expectedCurrentHostsHash: String?) async throws -> HostHelperWriteResult {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        if !shouldSucceed {
            if let error = simulatedError {
                throw error
            } else {
                throw HostHelperClientError.unavailable("模拟写入失败")
            }
        }

        writtenContents.append(contents)
        expectedHashes.append(expectedCurrentHostsHash)
        return HostHelperWriteResult(
            finalHostsHash: HostsHash.sha256Hex(contents),
            didRefreshDNS: true
        )
    }
}

extension FakeHostHelperClient {
    func setShouldSucceed(_ value: Bool) async {
        shouldSucceed = value
    }

    func setSimulatedError(_ error: Error?) async {
        simulatedError = error
    }

    func setDelayNanoseconds(_ value: UInt64) async {
        delayNanoseconds = value
    }
}

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

// MARK: - Stub DNS 刷新器

/// 测试用 DNS 刷新 stub
struct StubDNSRefresher: DNSRefreshing, Sendable {
    var shouldSucceed: Bool
    var errorMessage: String

    init(shouldSucceed: Bool = true, errorMessage: String = "stub DNS 刷新失败") {
        self.shouldSucceed = shouldSucceed
        self.errorMessage = errorMessage
    }

    func refreshDNSCache() throws {
        if !shouldSucceed {
            throw HostsWriteError.dnsRefreshFailed(errorMessage)
        }
    }
}
