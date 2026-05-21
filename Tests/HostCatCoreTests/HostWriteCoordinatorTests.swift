import XCTest
@testable import HostCatCore

// 用于测试的 fake helper client
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
        let coordinator = HostWriteCoordinator(helperClient: fakeClient, debounceInterval: .milliseconds(50))
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
        let coordinator = HostWriteCoordinator(helperClient: fakeClient)
        let config = makeConfig(defaultContent: "127.0.0.1 localhost\n::1 localhost")

        let (result, _) = await coordinator.scheduleApply(config: config)

        XCTAssertTrue(result.success)
        XCTAssertNotNil(result.appliedHash)
        XCTAssertNotNil(result.appliedAt)

        let writes = await fakeClient.writtenContents
        XCTAssertEqual(writes.count, 1)
    }

    func testFirstApplyUsesLastExternalHostsHashWhenNoAppliedHashExists() async {
        let fakeClient = FakeHostHelperClient()
        let coordinator = HostWriteCoordinator(helperClient: fakeClient, debounceInterval: .milliseconds(1))
        var config = makeConfig()
        config.state.lastExternalHostsHash = "external_hash"

        let (result, _) = await coordinator.scheduleApply(config: config)

        XCTAssertTrue(result.success)
        let hashes = await fakeClient.expectedHashes
        XCTAssertEqual(hashes, ["external_hash"])
    }

    func testWriteFailureDoesNotUpdateStateAndReturnsRolledBackConfig() async {
        let fakeClient = FakeHostHelperClient()
        await fakeClient.setShouldSucceed(false)
        let coordinator = HostWriteCoordinator(helperClient: fakeClient)
        let config = makeConfig()

        let (result, rolledBack) = await coordinator.scheduleApply(config: config)

        XCTAssertFalse(result.success)
        XCTAssertNil(result.appliedHash)
        XCTAssertNil(result.appliedAt)
        // 首次写入失败时，没有上次成功的快照，rolledBack 应为 nil
        XCTAssertNil(rolledBack)
    }

    func testWriteFailureRollsBackToLastSuccessfulConfig() async {
        let fakeClient = FakeHostHelperClient()
        let coordinator = HostWriteCoordinator(helperClient: fakeClient)
        let config1 = makeConfig(defaultContent: "127.0.0.1 localhost")
        let config2 = makeConfig(defaultContent: "10.0.0.1 bad.com")

        // 先成功写入一次
        let (result1, _) = await coordinator.scheduleApply(config: config1)
        XCTAssertTrue(result1.success)

        // 然后失败
        await fakeClient.setShouldSucceed(false)
        let (result2, rolledBack) = await coordinator.scheduleApply(config: config2)
        XCTAssertFalse(result2.success)

        // 应回滚到 config1
        XCTAssertNotNil(rolledBack)
        XCTAssertEqual(rolledBack?.defaultNode.content, "127.0.0.1 localhost")

        // coordinator 内部状态也应保持为 config1
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

        XCTAssertTrue(first.result.success)
        XCTAssertTrue(second.result.success)

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
        await fakeClient.setSimulatedError(HostHelperClientError.unavailable("hosts 已被外部修改"))

        let (result, _) = await coordinator.scheduleApply(config: config)

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

        let (result, _) = await coordinator.scheduleApply(config: config)

        XCTAssertFalse(result.success)
        XCTAssertNotNil(result.conflicts)
        XCTAssertEqual(result.conflicts?.count, 1)
        XCTAssertEqual(result.conflicts?.first?.hostname, "example.com")

        let writes = await fakeClient.writtenContents
        XCTAssertEqual(writes.count, 0)
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
