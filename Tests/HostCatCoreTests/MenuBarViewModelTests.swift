import XCTest
@testable import HostCatCore

@MainActor
final class MenuBarViewModelTests: XCTestCase {
    func testFailedApplyDoesNotDiscardEditedDraftConfig() async throws {
        let helper = FakeHostHelperClient()
        await helper.setShouldSucceed(false)
        let coordinator = HostWriteCoordinator(
            helperClient: helper,
            backupStore: nil,
            debounceInterval: .milliseconds(1)
        )
        let storeURL = makeStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }
        var config = AppConfig.initial(defaultHosts: "127.0.0.1 localhost\n")
        config.defaultNode.content = "10.0.0.1 draft.test\n"
        let viewModel = MenuBarViewModel(
            config: config,
            coordinator: coordinator,
            configStore: AppConfigStore(configURL: storeURL)
        )

        _ = await viewModel.applyImmediately()

        XCTAssertEqual(viewModel.config.defaultNode.content, "10.0.0.1 draft.test\n")
        XCTAssertNotNil(viewModel.applyError)
        let saved = try JSONDecoder.hostCatConfigDecoder.decode(AppConfig.self, from: Data(contentsOf: storeURL))
        XCTAssertEqual(saved.defaultNode.content, "10.0.0.1 draft.test\n")
    }

    func testFailedApplyWithRollbackSnapshotStillKeepsEditedDraftConfig() async throws {
        let helper = FakeHostHelperClient()
        let coordinator = HostWriteCoordinator(helperClient: helper, debounceInterval: .milliseconds(1))
        let storeURL = makeStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let viewModel = MenuBarViewModel(
            config: AppConfig.initial(defaultHosts: "127.0.0.1 localhost\n"),
            coordinator: coordinator,
            configStore: AppConfigStore(configURL: storeURL)
        )

        let first = await viewModel.applyImmediately()
        XCTAssertTrue(first.success)

        viewModel.config.defaultNode.content = "10.0.0.1 draft-after-success.test\n"
        await helper.setShouldSucceed(false)

        _ = await viewModel.applyImmediately()

        XCTAssertEqual(viewModel.config.defaultNode.content, "10.0.0.1 draft-after-success.test\n")
        XCTAssertNotNil(viewModel.applyError)
        let saved = try JSONDecoder.hostCatConfigDecoder.decode(AppConfig.self, from: Data(contentsOf: storeURL))
        XCTAssertEqual(saved.defaultNode.content, "10.0.0.1 draft-after-success.test\n")
    }

    func testImportConfigMergeUpdatesViewModelConfig() async throws {
        let helper = FakeHostHelperClient()
        let coordinator = HostWriteCoordinator(helperClient: helper, debounceInterval: .milliseconds(1))
        let storeURL = makeStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let viewModel = MenuBarViewModel(
            config: AppConfig.initial(defaultHosts: "127.0.0.1 localhost\n"),
            coordinator: coordinator,
            configStore: AppConfigStore(configURL: storeURL)
        )
        var imported = AppConfig.initial(defaultHosts: "ignored\n")
        imported.groups = [HostGroup(name: "G", nodes: [HostNode(name: "N", content: "1.1.1.1 n.test\n", isActive: true)])]

        let summary = viewModel.importConfig(imported, mode: .merge)

        XCTAssertEqual(summary.addedGroups, 1)
        XCTAssertEqual(viewModel.config.groups.first?.nodes.first?.name, "N")
        XCTAssertEqual(viewModel.config.defaultNode.content, "127.0.0.1 localhost\n")
        XCTAssertFalse(viewModel.config.groups[0].nodes[0].isActive)
    }

    func testExportConfigDataRoundTripsThroughDecode() throws {
        let coordinator = HostWriteCoordinator(helperClient: FakeHostHelperClient())
        var config = AppConfig.initial(defaultHosts: "127.0.0.1 localhost\n")
        config.groups = [HostGroup(name: "G", nodes: [HostNode(name: "N", content: "1.1.1.1 n.test\n", isActive: false)])]
        let viewModel = MenuBarViewModel(
            config: config,
            coordinator: coordinator,
            configStore: AppConfigStore(configURL: makeStoreURL())
        )

        let decoded = try viewModel.decodeImportedConfig(viewModel.exportConfigData())

        XCTAssertEqual(decoded.groups, config.groups)
    }

    func testApplyEmitsAppliedEventOnSuccess() async throws {
        let (viewModel, events, cleanup) = makeViewModelCollectingEvents(helper: FakeHostHelperClient())
        defer { cleanup() }

        _ = await viewModel.applyImmediately()

        XCTAssertEqual(events.values, [.applied])
    }

    func testApplyEmitsFailedEventOnWriteFailure() async throws {
        let helper = FakeHostHelperClient()
        await helper.setShouldSucceed(false)
        let (viewModel, events, cleanup) = makeViewModelCollectingEvents(helper: helper)
        defer { cleanup() }

        _ = await viewModel.applyImmediately()

        XCTAssertEqual(events.values.count, 1)
        guard case .failed = events.values[0] else {
            return XCTFail("应发出 failed 事件，实际：\(events.values)")
        }
    }

    func testApplyEmitsExternalModificationEventOnHashMismatch() async throws {
        let helper = FakeHostHelperClient()
        await helper.setShouldSucceed(false)
        await helper.setSimulatedError(HostHelperClientError.hashMismatch)
        let (viewModel, events, cleanup) = makeViewModelCollectingEvents(helper: helper)
        defer { cleanup() }

        _ = await viewModel.applyImmediately()

        XCTAssertEqual(events.values, [.externalModification])
    }

    func testApplyEmitsFailedEventOnConflicts() async throws {
        let (viewModel, events, cleanup) = makeViewModelCollectingEvents(helper: FakeHostHelperClient())
        defer { cleanup() }
        viewModel.config.groups = [HostGroup(name: "G", nodes: [
            HostNode(name: "A", content: "1.1.1.1 dup.test\n", isActive: true),
            HostNode(name: "B", content: "2.2.2.2 dup.test\n", isActive: true)
        ])]

        _ = await viewModel.applyImmediately()

        XCTAssertEqual(events.values.count, 1)
        guard case .failed = events.values[0] else {
            return XCTFail("冲突应发出 failed 事件，实际：\(events.values)")
        }
    }

    func testScheduledFailedApplyPersistsDraftConfig() async throws {
        let helper = FakeHostHelperClient()
        await helper.setShouldSucceed(false)
        let coordinator = HostWriteCoordinator(helperClient: helper, debounceInterval: .milliseconds(1))
        let storeURL = makeStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }
        var config = AppConfig.initial(defaultHosts: "127.0.0.1 localhost\n")
        config.defaultNode.content = "10.0.0.1 scheduled-draft.test\n"
        let viewModel = MenuBarViewModel(
            config: config,
            coordinator: coordinator,
            configStore: AppConfigStore(configURL: storeURL)
        )

        viewModel.scheduleApply()
        await waitForApplyToFinish(viewModel)

        XCTAssertEqual(viewModel.config.defaultNode.content, "10.0.0.1 scheduled-draft.test\n")
        XCTAssertNotNil(viewModel.applyError)
        let saved = try JSONDecoder.hostCatConfigDecoder.decode(AppConfig.self, from: Data(contentsOf: storeURL))
        XCTAssertEqual(saved.defaultNode.content, "10.0.0.1 scheduled-draft.test\n")
    }

    func testRestoreBackupFailureKeepsOriginalConfigAndPersistedConfig() async throws {
        let helper = FakeHostHelperClient()
        await helper.setShouldSucceed(false)
        let coordinator = HostWriteCoordinator(
            helperClient: helper,
            backupStore: nil,
            debounceInterval: .milliseconds(1)
        )
        let storeURL = makeStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }
        var originalConfig = AppConfig.initial(defaultHosts: "127.0.0.1 localhost\n")
        originalConfig.groups = [
            HostGroup(name: "开发", nodes: [
                HostNode(name: "API", content: "10.0.0.1 api.local\n", isActive: true),
            ]),
        ]
        try AppConfigStore(configURL: storeURL).save(originalConfig)
        let viewModel = MenuBarViewModel(
            config: originalConfig,
            coordinator: coordinator,
            configStore: AppConfigStore(configURL: storeURL)
        )
        let backupContent = """
        # --- HostCat Begin (v1) ---
        # 默认
        10.0.0.2 restored.local
        # --- HostCat End ---
        """

        let result = await viewModel.restoreBackup(content: backupContent)

        XCTAssertFalse(result.success)
        XCTAssertEqual(viewModel.config, originalConfig)
        let saved = try JSONDecoder.hostCatConfigDecoder.decode(AppConfig.self, from: Data(contentsOf: storeURL))
        XCTAssertEqual(saved, originalConfig)
    }

    func testForceApplyFailurePreservesStoredHashes() async throws {
        let helper = FakeHostHelperClient()
        await helper.setShouldSucceed(false)
        let coordinator = HostWriteCoordinator(
            helperClient: helper,
            backupStore: nil,
            debounceInterval: .milliseconds(1)
        )
        let storeURL = makeStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }
        var config = AppConfig.initial(defaultHosts: "127.0.0.1 localhost\n")
        config.state.lastAppliedHostsHash = "applied_hash"
        config.state.lastExternalHostsHash = "external_hash"
        let viewModel = MenuBarViewModel(
            config: config,
            coordinator: coordinator,
            configStore: AppConfigStore(configURL: storeURL)
        )

        viewModel.forceApply()
        await waitForApplyToFinish(viewModel)

        XCTAssertEqual(viewModel.config.state.lastAppliedHostsHash, "applied_hash")
        XCTAssertEqual(viewModel.config.state.lastExternalHostsHash, "external_hash")
        let saved = try JSONDecoder.hostCatConfigDecoder.decode(AppConfig.self, from: Data(contentsOf: storeURL))
        XCTAssertEqual(saved.state.lastAppliedHostsHash, "applied_hash")
        XCTAssertEqual(saved.state.lastExternalHostsHash, "external_hash")
        let expectedHashes = await helper.expectedHashes
        XCTAssertEqual(expectedHashes, [nil])
    }

    func testCancelledOlderApplyDoesNotClearApplyingStateForNewerApply() async {
        let helper = FakeHostHelperClient()
        let coordinator = HostWriteCoordinator(
            helperClient: helper,
            backupStore: nil,
            debounceInterval: .milliseconds(200)
        )
        let storeURL = makeStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let viewModel = MenuBarViewModel(
            config: AppConfig.initial(defaultHosts: "127.0.0.1 localhost\n"),
            coordinator: coordinator,
            configStore: AppConfigStore(configURL: storeURL)
        )

        viewModel.scheduleApply()
        viewModel.scheduleApply()
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertTrue(viewModel.isApplying)
    }

    // MARK: - Helper Recovery Prompt

    /// 当 apply 因 Helper 不可用失败时，viewModel 必须把状态映射成 `helperRecoveryPrompt`，
    /// 而不是设置 applyError；UI 才能弹出引导注册对话框，而不是只显示一条红色文字。
    func testHelperUnavailableErrorPopulatesRecoveryPrompt() async {
        let helper = FakeHostHelperClient()
        await helper.setShouldSucceed(false)
        await helper.setSimulatedError(HostHelperClientError.helperNotRegistered)
        let coordinator = HostWriteCoordinator(
            helperClient: helper,
            backupStore: nil,
            debounceInterval: .milliseconds(1)
        )
        let storeURL = makeStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let viewModel = MenuBarViewModel(
            config: AppConfig.initial(defaultHosts: "127.0.0.1 localhost\n"),
            coordinator: coordinator,
            configStore: AppConfigStore(configURL: storeURL)
        )

        _ = await viewModel.applyImmediately()

        XCTAssertNotNil(viewModel.helperRecoveryPrompt, "Helper 不可用时必须暴露 recovery prompt")
        XCTAssertNil(viewModel.applyError, "弹引导对话框时不应再显示底部红色 banner，避免重复打扰")
    }

    /// 用户在 Helper 引导对话框点「取消」/「稍后再说」后调用 dismiss，
    /// prompt 必须被清空且不会触发额外的 apply。
    func testDismissHelperRecoveryPromptClearsState() async {
        let helper = FakeHostHelperClient()
        await helper.setShouldSucceed(false)
        await helper.setSimulatedError(HostHelperClientError.helperNotRegistered)
        let coordinator = HostWriteCoordinator(
            helperClient: helper,
            backupStore: nil,
            debounceInterval: .milliseconds(1)
        )
        let viewModel = MenuBarViewModel(
            config: AppConfig.initial(defaultHosts: "127.0.0.1 localhost\n"),
            coordinator: coordinator,
            configStore: AppConfigStore(configURL: makeStoreURL())
        )

        _ = await viewModel.applyImmediately()
        XCTAssertNotNil(viewModel.helperRecoveryPrompt)

        viewModel.dismissHelperRecoveryPrompt()

        XCTAssertNil(viewModel.helperRecoveryPrompt)
    }

    /// 用户在系统设置启用 Helper 后点「我已开启，重试应用」时，
    /// viewModel 必须重新调用 helper 并在成功时把 prompt 清掉。
    func testRetryAfterHelperRecoveryClearsPromptOnSuccess() async {
        let helper = FakeHostHelperClient()
        await helper.setShouldSucceed(false)
        await helper.setSimulatedError(HostHelperClientError.helperNotApproved)
        let coordinator = HostWriteCoordinator(
            helperClient: helper,
            backupStore: nil,
            debounceInterval: .milliseconds(1)
        )
        let viewModel = MenuBarViewModel(
            config: AppConfig.initial(defaultHosts: "127.0.0.1 localhost\n"),
            coordinator: coordinator,
            configStore: AppConfigStore(configURL: makeStoreURL())
        )

        _ = await viewModel.applyImmediately()
        XCTAssertNotNil(viewModel.helperRecoveryPrompt)

        // 模拟用户在系统设置完成审批后 helper 可用
        await helper.setShouldSucceed(true)
        await helper.setSimulatedError(nil)

        let retryResult = await viewModel.retryApplyAfterHelperRecovery()

        XCTAssertTrue(retryResult.success)
        XCTAssertNil(viewModel.helperRecoveryPrompt, "重试成功后必须清空 prompt")
        let writes = await helper.writtenContents
        XCTAssertEqual(writes.count, 1, "重试时应当再调用一次 helper")
    }

    private func waitForApplyToFinish(
        _ viewModel: MenuBarViewModel,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while viewModel.isApplying && DispatchTime.now().uptimeNanoseconds < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// 收集 `applyEventHandler` 事件的小容器（主线程回调，测试同样在 MainActor）。
    private final class EventBox {
        var values: [ApplyNotificationEvent] = []
    }

    private func makeViewModelCollectingEvents(
        helper: FakeHostHelperClient
    ) -> (MenuBarViewModel, EventBox, () -> Void) {
        let coordinator = HostWriteCoordinator(helperClient: helper, backupStore: nil, debounceInterval: .milliseconds(1))
        let storeURL = makeStoreURL()
        let viewModel = MenuBarViewModel(
            config: AppConfig.initial(defaultHosts: "127.0.0.1 localhost\n"),
            coordinator: coordinator,
            configStore: AppConfigStore(configURL: storeURL)
        )
        let box = EventBox()
        viewModel.applyEventHandler = { box.values.append($0) }
        return (viewModel, box, { try? FileManager.default.removeItem(at: storeURL) })
    }

    private func makeStoreURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("HostCat-\(UUID().uuidString).json")
    }
}
