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

    private func waitForApplyToFinish(
        _ viewModel: MenuBarViewModel,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while viewModel.isApplying && DispatchTime.now().uptimeNanoseconds < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func makeStoreURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("HostCat-\(UUID().uuidString).json")
    }
}
