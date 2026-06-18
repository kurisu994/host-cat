import XCTest
@testable import HostCatCore

final class HostWriteCoordinatorTests: XCTestCase {

    private func makeConfig(defaultContent: String = "127.0.0.1 localhost") -> AppConfig {
        AppConfig(
            configVersion: 1,
            defaultNode: HostNode(name: "默认", content: defaultContent, isActive: true),
            groups: [],
            settings: AppSettings(launchAtLogin: false),
            state: AppStateMetadata()
        )
    }

    // MARK: - Debounce

    func testDebounceMergesRapidChanges() async {
        let fakeClient = FakeHostHelperClient()
        let coordinator = HostWriteCoordinator(
            helperClient: fakeClient,
            backupStore: nil,
            debounceInterval: .milliseconds(50)
        )
        let config = makeConfig()

        // 快速连续触发 3 次
        async let r1 = coordinator.scheduleApply(config: config)
        async let r2 = coordinator.scheduleApply(config: config)
        async let r3 = coordinator.scheduleApply(config: config)

        _ = await (r1, r2, r3)

        // 等待 debounce + 写入完成
        try? await Task.sleep(nanoseconds: 200_000_000)

        let writes = await fakeClient.writtenContents
        // debounce 后只应写入 1 次（最后一次没被取消的）
        XCTAssertEqual(writes.count, 1)
    }

    func testWriteSuccessUpdatesState() async {
        let fakeClient = FakeHostHelperClient()
        let coordinator = HostWriteCoordinator(helperClient: fakeClient, backupStore: nil)
        let config = makeConfig(defaultContent: "127.0.0.1 localhost\n::1 localhost")

        let result = await coordinator.scheduleApply(config: config)

        XCTAssertTrue(result.success)
        XCTAssertNotNil(result.appliedHash)
        XCTAssertNotNil(result.appliedAt)

        let writes = await fakeClient.writtenContents
        XCTAssertEqual(writes.count, 1)
    }

    func testFirstApplyUsesLastExternalHostsHashWhenNoAppliedHashExists() async {
        let fakeClient = FakeHostHelperClient()
        let coordinator = HostWriteCoordinator(
            helperClient: fakeClient,
            backupStore: nil,
            debounceInterval: .milliseconds(1)
        )
        var config = makeConfig()
        config.state.lastExternalHostsHash = "external_hash"

        let result = await coordinator.scheduleApply(config: config)

        XCTAssertTrue(result.success)
        let hashes = await fakeClient.expectedHashes
        XCTAssertEqual(hashes, ["external_hash"])
    }

    func testWriteFailureDoesNotUpdateStateNorSnapshot() async {
        let fakeClient = FakeHostHelperClient()
        await fakeClient.setShouldSucceed(false)
        let coordinator = HostWriteCoordinator(helperClient: fakeClient, backupStore: nil)
        let config = makeConfig()

        let result = await coordinator.scheduleApply(config: config)

        XCTAssertFalse(result.success)
        XCTAssertNil(result.appliedHash)
        XCTAssertNil(result.appliedAt)
        // 首次写入失败时，actor 内部也不应记录任何成功快照
        let snapshot = await coordinator.lastSuccessfulConfigSnapshot
        XCTAssertNil(snapshot)
    }

    func testWriteFailureKeepsLastSuccessfulSnapshotForServiceLayer() async {
        let fakeClient = FakeHostHelperClient()
        let coordinator = HostWriteCoordinator(helperClient: fakeClient, backupStore: nil)
        let config1 = makeConfig(defaultContent: "127.0.0.1 localhost")
        let config2 = makeConfig(defaultContent: "10.0.0.1 bad.com")

        // 先成功写入一次
        let result1 = await coordinator.scheduleApply(config: config1)
        XCTAssertTrue(result1.success)

        // 然后失败
        await fakeClient.setShouldSucceed(false)
        let result2 = await coordinator.scheduleApply(config: config2)
        XCTAssertFalse(result2.success)

        // coordinator 仍保留上次成功的快照供服务层判定真实 hosts 状态，
        // 但 UI 不再用它回滚草稿（草稿在 UI 层已通过 persistDraftConfig 持久化）。
        let lastSuccessful = await coordinator.lastSuccessfulConfigSnapshot
        XCTAssertEqual(lastSuccessful?.defaultNode.content, "127.0.0.1 localhost")
    }

    func testNewOperationsPreservedDuringWrite() async {
        let fakeClient = FakeHostHelperClient()
        // 模拟写入耗时 300ms
        await fakeClient.setDelayNanoseconds(300_000_000)
        let coordinator = HostWriteCoordinator(helperClient: fakeClient, debounceInterval: .milliseconds(50))
        let config1 = makeConfig(defaultContent: "127.0.0.1 localhost")
        let config2 = makeConfig(defaultContent: "127.0.0.1 localhost\n10.0.0.1 test.com")

        // 第一次立即写入会耗时 300ms，第二次请求必须在当前写入完成后继续应用
        async let r1 = coordinator.applyImmediately(config: config1)

        // 等待 100ms（写入进行中），然后触发第二次
        try? await Task.sleep(nanoseconds: 100_000_000)
        async let r2 = coordinator.scheduleApply(config: config2)

        let first = await r1
        let second = await r2

        XCTAssertTrue(first.success)
        XCTAssertTrue(second.success)

        let writes = await fakeClient.writtenContents
        XCTAssertEqual(writes.count, 2)
        XCTAssertTrue(writes[1].contains("10.0.0.1 test.com"))
    }

    func testHashMismatchPreventsOverwrite() async {
        let fakeClient = FakeHostHelperClient()
        let coordinator = HostWriteCoordinator(helperClient: fakeClient)
        var config = makeConfig()
        config.state.lastAppliedHostsHash = "mismatched_hash"

        // 模拟 helper 检测到 hash 不匹配
        await fakeClient.setShouldSucceed(false)
        await fakeClient.setSimulatedError(HostHelperClientError.hashMismatch)

        let result = await coordinator.scheduleApply(config: config)

        XCTAssertFalse(result.success)
    }

    func testConflictDetectionPreventsApply() async {
        let fakeClient = FakeHostHelperClient()
        let coordinator = HostWriteCoordinator(helperClient: fakeClient)

        let node1 = HostNode(name: "N1", content: "10.0.0.1 example.com", isActive: true)
        let node2 = HostNode(name: "N2", content: "10.0.0.2 example.com", isActive: true)
        var config = makeConfig()
        config.groups = [
            HostGroup(name: "G", isSingleSelect: false, nodes: [node1, node2])
        ]

        let result = await coordinator.scheduleApply(config: config)

        XCTAssertFalse(result.success)
        XCTAssertNotNil(result.conflicts)
        XCTAssertEqual(result.conflicts?.count, 1)
        XCTAssertEqual(result.conflicts?.first?.hostname, "example.com")

        let writes = await fakeClient.writtenContents
        XCTAssertEqual(writes.count, 0)
    }

    func testBackupFailurePreventsWrite() async throws {
        let fakeClient = FakeHostHelperClient()
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let hostsURL = directory.appendingPathComponent("hosts")
        try "127.0.0.1 localhost\n".write(to: hostsURL, atomically: true, encoding: .utf8)

        let blockingFile = directory.appendingPathComponent("backup-blocker")
        try Data("not a directory".utf8).write(to: blockingFile)

        let coordinator = HostWriteCoordinator(
            helperClient: fakeClient,
            backupStore: BackupStore(backupDirectory: blockingFile),
            hostsPath: hostsURL.path,
            debounceInterval: .milliseconds(1)
        )

        let result = await coordinator.applyImmediately(config: makeConfig())

        XCTAssertFalse(result.success)
        if case .writeFailed(let message) = result.status {
            XCTAssertTrue(message.contains("备份"))
        } else {
            XCTFail("预期备份失败应返回 writeFailed")
        }
        let writes = await fakeClient.writtenContents
        XCTAssertEqual(writes.count, 0)
    }

    // MARK: - 失败语义补充

    /// hash mismatch 失败后不应自动重试。helper 只被调用一次，
    /// 后续重试必须由用户显式选择导入/取消/覆盖。
    func testHashMismatchDoesNotAutoRetry() async {
        let fakeClient = FakeHostHelperClient()
        var config = makeConfig()
        config.state.lastAppliedHostsHash = "stale_hash"

        await fakeClient.setShouldSucceed(false)
        await fakeClient.setSimulatedError(HostHelperClientError.hashMismatch)

        let coordinator = HostWriteCoordinator(
            helperClient: fakeClient,
            backupStore: nil,
            debounceInterval: .milliseconds(1)
        )

        let result = await coordinator.scheduleApply(config: config)
        XCTAssertFalse(result.success)

        // 等待一段时间，确认 coordinator 没有内部触发新的写入尝试
        try? await Task.sleep(nanoseconds: 200_000_000)

        let writes = await fakeClient.writtenContents
        XCTAssertEqual(writes.count, 0, "失败后不应自动重试")
        let attempts = await fakeClient.expectedHashes
        XCTAssertEqual(attempts.count, 1, "helper 应只被调用一次")
    }

    /// 当前批次写入失败时，后续到达的新批次必须能继续被独立处理，
    /// 不被失败状态阻塞，且不会与失败批次的内容混合。
    func testFailedBatchDoesNotBlockSubsequentBatch() async {
        let fakeClient = FakeHostHelperClient()
        let coordinator = HostWriteCoordinator(
            helperClient: fakeClient,
            backupStore: nil,
            debounceInterval: .milliseconds(1)
        )

        let config1 = makeConfig(defaultContent: "127.0.0.1 localhost")
        let config2 = makeConfig(defaultContent: "127.0.0.1 localhost\n10.0.0.1 retry.test")

        // 第一次失败
        await fakeClient.setShouldSucceed(false)
        let result1 = await coordinator.scheduleApply(config: config1)
        XCTAssertFalse(result1.success, "第一次写入应失败")

        // 第二次新批次必须能继续执行并成功（失败状态不阻塞后续）
        await fakeClient.setShouldSucceed(true)
        let result2 = await coordinator.scheduleApply(config: config2)
        XCTAssertTrue(result2.success, "失败后的新批次必须能继续被处理")

        // 失败批次不应有写入记录；成功批次写入的是新内容（非失败批次）
        let writes = await fakeClient.writtenContents
        XCTAssertEqual(writes.count, 1, "只有第二次（成功的）写入应被记录")
        XCTAssertTrue(writes[0].contains("10.0.0.1 retry.test"),
                      "实际写入的应是新批次内容，不被失败批次污染")
    }

    // MARK: - Helper Unavailable 状态分流

    /// 当 helper 抛出 `unavailable` / `helperNotRegistered` / `connectionInvalidated`
    /// 等"整个 Helper 不可用"类错误时，coordinator 必须返回 `.helperUnavailable`，
    /// 让 UI 走辅助注册引导，而不是当作普通 writeFailed 显示红色 banner。
    func testHelperUnavailableErrorMapsToHelperUnavailableStatus() async {
        let cases: [(HostHelperClientError, String)] = [
            (.unavailable("mach service 未启动"), "unavailable"),
            (.helperNotRegistered, "helperNotRegistered"),
            (.helperNotApproved, "helperNotApproved"),
            (.connectionInterrupted, "connectionInterrupted"),
            (.connectionInvalidated, "connectionInvalidated"),
        ]

        for (error, label) in cases {
            let fakeClient = FakeHostHelperClient()
            await fakeClient.setShouldSucceed(false)
            await fakeClient.setSimulatedError(error)
            let coordinator = HostWriteCoordinator(
                helperClient: fakeClient,
                backupStore: nil,
                debounceInterval: .milliseconds(1)
            )

            let result = await coordinator.scheduleApply(config: makeConfig())

            XCTAssertFalse(result.success, "\(label) 应当失败")
            if case .helperUnavailable = result.status {
                // 期望分支
            } else {
                XCTFail("\(label) 应映射到 .helperUnavailable，实际: \(result.status)")
            }
        }
    }

    /// `hashMismatch` / `fileImmutable` 等真实写入错误必须仍走 `.writeFailed`，
    /// 不能被新的 helper 引导路径吞掉。
    func testWriteErrorStillReportsWriteFailed() async {
        let writeErrors: [HostHelperClientError] = [
            .hashMismatch,
            .fileImmutable,
            .requestTimedOut,
            .unexpectedReply("missing finalHash"),
        ]

        for error in writeErrors {
            let fakeClient = FakeHostHelperClient()
            await fakeClient.setShouldSucceed(false)
            await fakeClient.setSimulatedError(error)
            let coordinator = HostWriteCoordinator(
                helperClient: fakeClient,
                backupStore: nil,
                debounceInterval: .milliseconds(1)
            )

            let result = await coordinator.scheduleApply(config: makeConfig())

            XCTAssertFalse(result.success)
            if case .writeFailed = result.status {
                // 期望分支
            } else {
                XCTFail("\(error) 应保持 .writeFailed，实际: \(result.status)")
            }
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HostCatCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
