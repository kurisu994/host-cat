import Combine
import Foundation
import os.log

/// Node information for menu bar display.
public struct MenuBarNodeItem: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var isActive: Bool
    public var groupID: UUID?

    public init(id: UUID, name: String, isActive: Bool, groupID: UUID? = nil) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.groupID = groupID
    }
}

/// Helper 不可用时呈现给 UI 的引导信息，包含原始错误描述。
/// 设计为 Identifiable，方便 SwiftUI `.alert(item:)` / `.sheet(item:)` 直接绑定。
public struct HelperRecoveryPrompt: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let errorMessage: String

    public init(id: UUID = UUID(), errorMessage: String) {
        self.id = id
        self.errorMessage = errorMessage
    }
}

/// Group information for menu bar display.
public struct MenuBarGroupItem: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var isSingleSelect: Bool
    public var nodes: [MenuBarNodeItem]

    public init(id: UUID, name: String, isSingleSelect: Bool, nodes: [MenuBarNodeItem]) {
        self.id = id
        self.name = name
        self.isSingleSelect = isSingleSelect
        self.nodes = nodes
    }
}

/// Menu bar view model that maintains in-memory config state and interacts with HostWriteCoordinator.
@MainActor
public final class MenuBarViewModel: ObservableObject {
    @Published public var config: AppConfig
    @Published public var applyError: String?
    @Published public var isApplying = false
    @Published public var lastMergedText: String?
    @Published public var lastDuplicateCount: Int = 0
    @Published public var lastConflicts: [HostConflict] = []

    // External modification detection
    @Published public var showExternalModificationAlert = false
    @Published public var externalModificationContent: String?

    /// 当 Apply 失败原因属于 Helper 不可用时，UI 通过此值弹出引导注册的对话框。
    /// 引导完成后调用 `retryApplyAfterHelperRecovery()` 重新触发写入。
    @Published public var helperRecoveryPrompt: HelperRecoveryPrompt?

    /// 写入流程结果事件回调，App 层据此发送系统通知；Core 不依赖 UserNotifications。
    public var applyEventHandler: (@MainActor (ApplyNotificationEvent) -> Void)?

    private let mutationService = ConfigMutationService()
    private let coordinator: HostWriteCoordinator
    private let configStore: AppConfigStore
    private let logger = Logger(subsystem: "com.hostcat.app", category: "MenuBarViewModel")
    private var applyGeneration = 0

    public init(
        config: AppConfig,
        coordinator: HostWriteCoordinator,
        configStore: AppConfigStore = AppConfigStore()
    ) {
        self.config = config
        self.coordinator = coordinator
        self.configStore = configStore
    }

    // MARK: - Menu Bar Items

    public var defaultNodeItem: MenuBarNodeItem {
        MenuBarNodeItem(
            id: config.defaultNode.id,
            name: config.defaultNode.name,
            isActive: config.defaultNode.isActive
        )
    }

    public var groupItems: [MenuBarGroupItem] {
        config.groups.map { group in
            MenuBarGroupItem(
                id: group.id,
                name: group.name,
                isSingleSelect: group.isSingleSelect,
                nodes: group.nodes.map { node in
                    MenuBarNodeItem(
                        id: node.id,
                        name: node.name,
                        isActive: node.isActive,
                        groupID: group.id
                    )
                }
            )
        }
    }

    // MARK: - Node Activation

    public func toggleNode(id: UUID, inGroup groupID: UUID?) {
        if let groupID = groupID {
            guard let groupIndex = config.groups.firstIndex(where: { $0.id == groupID }) else {
                logger.warning("Attempted to toggle non-existent group: \(groupID.uuidString, privacy: .public)")
                return
            }
            guard let nodeIndex = config.groups[groupIndex].nodes.firstIndex(where: { $0.id == id }) else {
                logger.warning("Attempted to toggle non-existent node: \(id.uuidString, privacy: .public)")
                return
            }
            let currentActive = config.groups[groupIndex].nodes[nodeIndex].isActive
            let nodeName = config.groups[groupIndex].nodes[nodeIndex].name
            mutationService.setNodeActive(
                id: id,
                active: !currentActive,
                inGroup: groupID,
                in: &config
            )
            logger.info("Node \(nodeName, privacy: .public) toggled to \(!currentActive, privacy: .public)")
        } else {
            // 默认节点恒激活，配置没有变化，不触发写入。
            logger.debug("Default node toggle ignored")
            return
        }

        // Trigger debounced write
        scheduleApply()
    }

    // MARK: - Apply

    public func scheduleApply() {
        isApplying = true
        applyError = nil
        lastConflicts = []
        let generation = nextApplyGeneration()

        Task {
            guard persistDraftConfig() else {
                finishApplyIfCurrent(generation)
                return
            }

            let result = await coordinator.scheduleApply(config: config)
            guard isCurrentApplyGeneration(generation) else {
                recordSupersededSuccess(result)
                return
            }
            isApplying = false
            handleApplyCompletion(result: result, failureLogPrefix: "Write failed")
        }
    }

    public func applyImmediately() async -> ApplyResult {
        isApplying = true
        applyError = nil
        lastConflicts = []
        let generation = nextApplyGeneration()

        guard persistDraftConfig() else {
            finishApplyIfCurrent(generation)
            let message = applyError ?? LC.configSaveFailed
            return ApplyResult(
                success: false,
                errorMessage: message,
                status: .writeFailed(message)
            )
        }

        let result = await coordinator.applyImmediately(config: config)

        guard isCurrentApplyGeneration(generation) else {
            recordSupersededSuccess(result)
            return result
        }
        isApplying = false
        handleApplyCompletion(result: result, failureLogPrefix: "Immediate apply failed")

        return result
    }

    /// Restore configuration from hosts backup content; current draft config is not replaced until write succeeds.
    public func restoreBackup(content: String) async -> ApplyResult {
        isApplying = true
        applyError = nil
        lastConflicts = []
        let generation = nextApplyGeneration()

        let importResult = HostsImporter().importHosts(content)
        var restoredConfig = config
        restoredConfig.defaultNode.content = importResult.safeDefaultNodeContent
        for groupIndex in restoredConfig.groups.indices {
            for nodeIndex in restoredConfig.groups[groupIndex].nodes.indices {
                restoredConfig.groups[groupIndex].nodes[nodeIndex].isActive = false
            }
        }

        let result = await coordinator.applyImmediately(config: restoredConfig)

        guard isCurrentApplyGeneration(generation) else {
            recordSupersededSuccess(result)
            return result
        }
        isApplying = false

        if result.success {
            config = restoredConfig
        }
        handleApplyCompletion(result: result, failureLogPrefix: "Backup restore failed")

        return result
    }

    /// Force write, skipping hash validation (used after user confirms overwriting external changes).
    public func forceApply() {
        isApplying = true
        applyError = nil
        lastConflicts = []
        let generation = nextApplyGeneration()

        Task {
            guard persistDraftConfig() else {
                finishApplyIfCurrent(generation)
                return
            }

            let result = await coordinator.scheduleApply(config: config, force: true)
            guard isCurrentApplyGeneration(generation) else {
                recordSupersededSuccess(result)
                return
            }
            isApplying = false
            handleApplyCompletion(result: result, failureLogPrefix: "Force write failed")
        }
    }

    private func handleApplyCompletion(
        result: ApplyResult,
        failureLogPrefix: String
    ) {
        if !result.success {
            logger.warning("\(failureLogPrefix, privacy: .public), keeping current config draft, hosts not applied")
        }

        if result.success {
            if let error = recordAppliedState(result) {
                applyError = LC.configSaveFailed + ": \(error.localizedDescription)"
            }
            updateMergedPreview()
            if result.didRefreshDNS == false {
                // 文件已写入，只是 DNS 没确认刷新：提示用户留意，但不能当成写入失败。
                let message = LC.dnsRefreshUnconfirmed
                applyError = message
                applyEventHandler?(.appliedWithWarning(message))
            } else {
                applyEventHandler?(.applied)
            }
        } else if case .hashMismatch = result.status {
            showExternalModificationAlert = true
            applyError = LC.externalModificationDetected
            applyEventHandler?(.externalModification)
            logger.warning("\(LC.logExternalModification, privacy: .public)")
        } else if let conflicts = result.conflicts {
            lastConflicts = conflicts
            applyError = LC.conflictsDetected(conflicts.count)
            applyEventHandler?(.failed(LC.conflictsDetected(conflicts.count)))
            logger.warning("\(LC.logMergeConflicts(count: conflicts.count), privacy: .public)")
        } else if let errorMessage = result.errorMessage {
            // Distinguish helper-unavailable / external-modification / other write errors.
            if case .helperUnavailable(let msg) = result.status {
                // Helper 没就绪，不再用纯文字 banner，而是抛给 UI 的辅助注册流程。
                helperRecoveryPrompt = HelperRecoveryPrompt(errorMessage: msg)
                applyError = nil
                applyEventHandler?(.failed(LC.hostsNotApplied(msg)))
                logger.warning("Helper unavailable: \(msg, privacy: .public)")
            } else {
                applyError = LC.hostsNotApplied(errorMessage)
                applyEventHandler?(.failed(LC.hostsNotApplied(errorMessage)))
                logger.error("\(LC.logApplyFailed(failureLogPrefix, errorMessage), privacy: .public)")
            }
        }
    }

    /// 把成功写入的 hash 和时间记进配置并落盘；保存失败时返回错误。
    private func recordAppliedState(_ result: ApplyResult) -> Error? {
        if let hash = result.appliedHash {
            config.state.lastAppliedHostsHash = hash
        }
        if let at = result.appliedAt {
            config.state.lastAppliedAt = at
        }
        do {
            try configStore.save(config)
            logger.info("\(LC.logConfigPersistSuccess, privacy: .public)")
            return nil
        } catch {
            logger.error("\(LC.logConfigPersistFailed(error.localizedDescription), privacy: .public)")
            return error
        }
    }

    /// 被新请求取代的写入如果成功了，磁盘已经是它的内容，仍要记下 hash；
    /// 否则配置里留着旧 hash，下次启动或下次写入会误判成外部修改。
    private func recordSupersededSuccess(_ result: ApplyResult) {
        guard result.success else { return }
        // 更新的写入已经先记录过时不要回退。
        if let current = config.state.lastAppliedAt,
           let appliedAt = result.appliedAt,
           appliedAt < current {
            return
        }
        _ = recordAppliedState(result)
    }

    // MARK: - Config Import / Export

    /// 导出当前配置（已清除本机 state）。
    public func exportConfigData() throws -> Data {
        try ConfigTransferService().exportData(config)
    }

    /// 解析导入文件，校验失败时抛出 `ConfigTransferError`，不改动当前配置。
    public func decodeImportedConfig(_ data: Data) throws -> AppConfig {
        try ConfigTransferService().decode(data)
    }

    /// 按所选模式应用导入配置，并触发一次延迟写入。
    @discardableResult
    public func importConfig(_ imported: AppConfig, mode: ConfigImportMode) -> ConfigImportSummary {
        let result = ConfigTransferService().apply(imported, to: config, mode: mode)
        config = result.config
        logger.info("Config imported, mode=\(String(describing: mode), privacy: .public), addedGroups=\(result.summary.addedGroups, privacy: .public), addedNodes=\(result.summary.addedNodes, privacy: .public), updatedNodes=\(result.summary.updatedNodes, privacy: .public)")
        scheduleApply()
        return result.summary
    }

    // MARK: - Helper Recovery

    /// 用户在 Helper 引导对话框中点了「取消」时清空提示，不重试。
    public func dismissHelperRecoveryPrompt() {
        helperRecoveryPrompt = nil
    }

    /// 用户在 Helper 引导对话框完成注册/审批后调用，立即重试写入。
    @discardableResult
    public func retryApplyAfterHelperRecovery() async -> ApplyResult {
        helperRecoveryPrompt = nil
        return await applyImmediately()
    }

    private func persistDraftConfig() -> Bool {
        do {
            try configStore.save(config)
            logger.info("\(LC.logDraftPersistSuccess, privacy: .public)")
            return true
        } catch {
            logger.error("\(LC.logDraftPersistFailed(error.localizedDescription), privacy: .public)")
            applyError = LC.configSaveFailed + ": \(error.localizedDescription)"
            return false
        }
    }

    private func nextApplyGeneration() -> Int {
        applyGeneration += 1
        return applyGeneration
    }

    private func isCurrentApplyGeneration(_ generation: Int) -> Bool {
        generation == applyGeneration
    }

    private func finishApplyIfCurrent(_ generation: Int) {
        guard isCurrentApplyGeneration(generation) else { return }
        isApplying = false
    }

    // MARK: - Preview

    public func updateMergedPreview() {
        do {
            let merged = try HostsMerger().merge(config)
            lastMergedText = merged.text
            lastDuplicateCount = merged.duplicateCount
            logger.debug("\(LC.logMergePreview(merged.records.count, merged.duplicateCount), privacy: .public)")
        } catch let HostMergeError.conflicts(conflicts) {
            lastConflicts = conflicts
            applyError = LC.conflictsDetected(conflicts.count)
            logger.warning("\(LC.logPreviewConflicts(conflicts.count), privacy: .public)")
        } catch {
            applyError = error.localizedDescription
            logger.error("\(LC.logPreviewMergeFailed(error.localizedDescription), privacy: .public)")
        }
    }

    public func clearError() {
        applyError = nil
    }

    /// 启动时配置被重置或加载失败，在菜单和编辑器状态栏提示用户，避免分组「凭空消失」。
    public func noteStartupNotice(_ message: String) {
        applyError = message
        logger.warning("Startup notice: \(message, privacy: .public)")
    }

    /// 启动时对照磁盘 hash，标出还没写入，或被外面改过。
    public func noteStartupDrift(diskHash: String) {
        let mergedText = (try? HostsMerger().merge(config))?.text
        switch HostsDriftChecker.evaluate(
            diskHash: diskHash,
            lastAppliedHostsHash: config.state.lastAppliedHostsHash,
            lastExternalHostsHash: config.state.lastExternalHostsHash,
            mergedText: mergedText
        ) {
        case .inSync:
            break
        case .unapplied:
            applyError = LC.unappliedHosts
        case .externallyModified:
            showExternalModificationAlert = true
            applyError = LC.externalModificationDetected
        }
    }
}
