import Foundation
import XCTest
@testable import HostCatCore

/// 只使用内存 Helper 和临时 config.json，不读取或写入真实 hosts，不触发 DNS/XPC。
@MainActor
final class AuditConcurrencyRegressionTests: XCTestCase {
    private let systemHosts = "127.0.0.1 localhost\n255.255.255.255 broadcasthost\n::1 localhost\n"

    /// A 写入期间提交 B；B 必须衔接 A 的成功 hash，而不能把自身写入误报为外部修改。
    func testQueuedApplyRebasesHashAndPersistsLatestSuccessfulState() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppConfigStore(configURL: directory.appendingPathComponent("config.json"))
        let initialHash = HostsHash.sha256Hex(systemHosts)
        var config = AppConfig.initial(defaultHosts: systemHosts, currentHostsHash: initialHash)
        config.defaultNode.content += "10.0.0.1 first.audit.test\n"
        let helper = AuditHashCheckingGateHelper(currentHash: initialHash, holdFirst: true)
        let coordinator = HostWriteCoordinator(helperClient: helper, backupStore: nil)
        let viewModel = MenuBarViewModel(config: config, coordinator: coordinator, configStore: store)

        let firstTask = Task { @MainActor in await viewModel.applyImmediately() }
        await helper.waitForAttempts(1)
        let firstHash = try HostsHash.sha256Hex(HostsMerger().merge(viewModel.config).text)

        viewModel.config.defaultNode.content += "10.0.0.2 second.audit.test\n"
        let finalText = try HostsMerger().merge(viewModel.config).text
        let finalHash = HostsHash.sha256Hex(finalText)
        var secondStarted = false
        let secondTask = Task { @MainActor in
            secondStarted = true
            // 同一 MainActor 的调用在首次 await coordinator 前已提升 generation 并保存草稿。
            return await viewModel.applyImmediately()
        }
        while !secondStarted { await Task.yield() }
        await helper.releaseFirst()

        let first = await firstTask.value
        let second = await secondTask.value
        let attempts = await helper.attempts
        let written = await helper.writtenContents
        XCTAssertTrue(first.success)
        XCTAssertTrue(second.success, "新批次应衔接自己的上次写入，而非 hashMismatch")
        XCTAssertEqual(attempts.map(\.expectedHash), [initialHash, firstHash])
        XCTAssertEqual(written.last, finalText)
        XCTAssertEqual(viewModel.config.state.lastAppliedHostsHash, finalHash)
        XCTAssertFalse(viewModel.showExternalModificationAlert)
        let saved = try JSONDecoder.hostCatConfigDecoder.decode(AppConfig.self, from: Data(contentsOf: store.configURL))
        XCTAssertEqual(saved.state.lastAppliedHostsHash, finalHash)
        XCTAssertTrue(saved.defaultNode.content.contains("second.audit.test"))
    }

    /// 恢复因 hashMismatch 失败后，确认覆盖仍应应用选中的备份，不能改写成当前草稿。
    func testRestoreForceRetryRetainsSelectedBackupIntent() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppConfigStore(configURL: directory.appendingPathComponent("config.json"))
        let initialHash = HostsHash.sha256Hex(systemHosts)
        var config = AppConfig.initial(defaultHosts: systemHosts, currentHostsHash: initialHash)
        config.defaultNode.content += "10.0.0.1 draft.audit.test\n"
        let externalHash = HostsHash.sha256Hex(systemHosts + "10.0.0.3 external.audit.test\n")
        let helper = AuditHashCheckingGateHelper(currentHash: externalHash)
        let coordinator = HostWriteCoordinator(helperClient: helper, backupStore: nil, debounceInterval: .zero)
        let viewModel = MenuBarViewModel(config: config, coordinator: coordinator, configStore: store)
        let backup = systemHosts + "10.0.0.2 backup.audit.test\n"

        let failed = await viewModel.restoreBackup(content: backup)
        XCTAssertFalse(failed.success)
        XCTAssertTrue(viewModel.showExternalModificationAlert)
        XCTAssertEqual(viewModel.config, config, "失败时先保持草稿是正确的事务语义")

        // 与 ExternalModificationAlert 的覆盖按钮一致。
        viewModel.forceApply()
        await helper.waitForAttempts(2)
        while viewModel.isApplying { await Task.yield() }

        let attempts = await helper.attempts
        let written = await helper.writtenContents
        XCTAssertNil(attempts.last?.expectedHash)
        XCTAssertTrue(written.last?.contains("backup.audit.test") == true, "确认覆盖应继续恢复备份")
        XCTAssertFalse(written.last?.contains("draft.audit.test") == true, "不能把恢复重试替换成草稿写入")
        XCTAssertTrue(viewModel.config.defaultNode.content.contains("backup.audit.test"))
        let saved = try JSONDecoder.hostCatConfigDecoder.decode(AppConfig.self, from: Data(contentsOf: store.configURL))
        XCTAssertTrue(saved.defaultNode.content.contains("backup.audit.test"))
    }

    /// 恢复在 Helper 未审批时失败，审批后的重试也必须保留备份恢复意图。
    func testRestoreHelperRecoveryRetryRetainsSelectedBackupIntent() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppConfigStore(configURL: directory.appendingPathComponent("config.json"))
        let initialHash = HostsHash.sha256Hex(systemHosts)
        var config = AppConfig.initial(defaultHosts: systemHosts, currentHostsHash: initialHash)
        config.defaultNode.content += "10.0.0.1 draft.audit.test\n"
        let helper = AuditHashCheckingGateHelper(currentHash: initialHash, firstError: .helperNotApproved)
        let coordinator = HostWriteCoordinator(helperClient: helper, backupStore: nil)
        let viewModel = MenuBarViewModel(config: config, coordinator: coordinator, configStore: store)

        let failed = await viewModel.restoreBackup(content: systemHosts + "10.0.0.2 backup.audit.test\n")
        XCTAssertFalse(failed.success)
        XCTAssertNotNil(viewModel.helperRecoveryPrompt)
        XCTAssertEqual(viewModel.config, config)

        let retried = await viewModel.retryApplyAfterHelperRecovery()
        XCTAssertTrue(retried.success)
        let written = await helper.writtenContents
        XCTAssertTrue(written.last?.contains("backup.audit.test") == true, "审批后重试应继续恢复所选备份")
        XCTAssertFalse(written.last?.contains("draft.audit.test") == true)
        XCTAssertTrue(viewModel.config.defaultNode.content.contains("backup.audit.test"))
        let saved = try JSONDecoder.hostCatConfigDecoder.decode(AppConfig.self, from: Data(contentsOf: store.configURL))
        XCTAssertTrue(saved.defaultNode.content.contains("backup.audit.test"))
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HostCat-Audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

/// 带确定性首请求闸门、真实 SHA256 校验的 Helper 替身；不会访问文件系统。
private actor AuditHashCheckingGateHelper: HostHelperClient {
    struct Attempt: Sendable {
        let contents: String
        let expectedHash: String?
    }

    private(set) var attempts: [Attempt] = []
    private(set) var writtenContents: [String] = []
    private var currentHash: String
    private let holdFirst: Bool
    private let firstError: HostHelperClientError?
    private var firstContinuation: CheckedContinuation<Void, Never>?
    private var attemptWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(currentHash: String, holdFirst: Bool = false, firstError: HostHelperClientError? = nil) {
        self.currentHash = currentHash
        self.holdFirst = holdFirst
        self.firstError = firstError
    }

    func writeHosts(_ contents: String, expectedCurrentHostsHash: String?) async throws -> HostHelperWriteResult {
        attempts.append(Attempt(contents: contents, expectedHash: expectedCurrentHostsHash))
        let index = attempts.count
        let ready = attemptWaiters.filter { $0.count <= index }
        attemptWaiters.removeAll { $0.count <= index }
        for waiter in ready { waiter.continuation.resume() }

        if index == 1, holdFirst {
            await withCheckedContinuation { firstContinuation = $0 }
        }
        if index == 1, let firstError { throw firstError }
        if let expectedCurrentHostsHash, expectedCurrentHostsHash != currentHash {
            throw HostHelperClientError.hashMismatch
        }
        currentHash = HostsHash.sha256Hex(contents)
        writtenContents.append(contents)
        return HostHelperWriteResult(finalHostsHash: currentHash, didRefreshDNS: true)
    }

    func waitForAttempts(_ count: Int) async {
        guard attempts.count < count else { return }
        await withCheckedContinuation { attemptWaiters.append((count, $0)) }
    }

    func releaseFirst() {
        firstContinuation?.resume()
        firstContinuation = nil
    }
}
