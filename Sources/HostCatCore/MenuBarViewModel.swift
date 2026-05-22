import Combine
import Foundation
import os.log

/// 菜单栏展示用的节点信息
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

/// 菜单栏展示用的分组信息
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

/// 菜单栏视图模型，负责维护内存配置状态、与 HostWriteCoordinator 交互
@MainActor
public final class MenuBarViewModel: ObservableObject {
    @Published public var config: AppConfig
    @Published public var applyError: String?
    @Published public var isApplying = false
    @Published public var lastMergedText: String?
    @Published public var lastDuplicateCount: Int = 0
    @Published public var lastConflicts: [HostConflict] = []

    // 外部修改检测
    @Published public var showExternalModificationAlert = false
    @Published public var externalModificationContent: String?

    // Helper 状态提示
    @Published public var showHelperRegistrationAlert = false

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
                logger.warning("尝试切换不存在的分组: \(groupID.uuidString)")
                return
            }
            guard let nodeIndex = config.groups[groupIndex].nodes.firstIndex(where: { $0.id == id }) else {
                logger.warning("尝试切换不存在的节点: \(id.uuidString)")
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
            logger.info("节点 \(nodeName) 状态切换为 \(!currentActive)")
        } else {
            // 默认节点不可停用
            logger.debug("尝试切换默认节点，已忽略")
        }

        // 触发 debounce 写入
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

            let (result, rolledBackConfig) = await coordinator.scheduleApply(config: config)
            guard isCurrentApplyGeneration(generation) else {
                return
            }
            isApplying = false
            handleApplyCompletion(result: result, rolledBackConfig: rolledBackConfig, failureLogPrefix: "写入失败")
        }
    }

    public func applyImmediately() async -> ApplyResult {
        isApplying = true
        applyError = nil
        lastConflicts = []
        let generation = nextApplyGeneration()

        guard persistDraftConfig() else {
            finishApplyIfCurrent(generation)
            let message = applyError ?? "配置保存失败"
            return ApplyResult(
                success: false,
                errorMessage: message,
                status: .writeFailed(message)
            )
        }

        let (result, rolledBackConfig) = await coordinator.applyImmediately(config: config)

        guard isCurrentApplyGeneration(generation) else {
            return result
        }
        isApplying = false
        handleApplyCompletion(result: result, rolledBackConfig: rolledBackConfig, failureLogPrefix: "即时应用失败")

        return result
    }

    /// 从 hosts 备份内容恢复配置；写入成功前不替换当前草稿配置。
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

        let (result, rolledBackConfig) = await coordinator.applyImmediately(config: restoredConfig)

        guard isCurrentApplyGeneration(generation) else {
            return result
        }
        isApplying = false

        if result.success {
            config = restoredConfig
        }
        handleApplyCompletion(result: result, rolledBackConfig: rolledBackConfig, failureLogPrefix: "备份恢复失败")

        return result
    }

    /// 强制写入，跳过 hash 校验（用于用户确认覆盖外部修改后）
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

            let (result, rolledBackConfig) = await coordinator.scheduleApply(config: config, force: true)
            guard isCurrentApplyGeneration(generation) else {
                return
            }
            isApplying = false
            handleApplyCompletion(result: result, rolledBackConfig: rolledBackConfig, failureLogPrefix: "强制写入失败")
        }
    }

    private func handleApplyCompletion(
        result: ApplyResult,
        rolledBackConfig: AppConfig?,
        failureLogPrefix: String
    ) {
        if !result.success, rolledBackConfig != nil {
            logger.warning("\(failureLogPrefix)，保留当前配置草稿，hosts 未应用")
        }

        if result.success {
            if let hash = result.appliedHash {
                config.state.lastAppliedHostsHash = hash
            }
            if let at = result.appliedAt {
                config.state.lastAppliedAt = at
            }
            do {
                try configStore.save(config)
                logger.info("应用配置持久化成功")
            } catch {
                logger.error("应用配置持久化失败: \(error.localizedDescription)")
                applyError = "配置保存失败: \(error.localizedDescription)"
            }
            updateMergedPreview()
        } else if let conflicts = result.conflicts {
            lastConflicts = conflicts
            applyError = "检测到 \(conflicts.count) 个冲突，请解决后再应用"
            logger.warning("应用冲突: \(conflicts.count) 个")
        } else if let errorMessage = result.errorMessage {
            // 区分外部修改和其他写入错误
            if case .writeFailed(let msg) = result.status,
               msg == HostHelperClientError.hashMismatch.localizedDescription {
                showExternalModificationAlert = true
                applyError = "hosts 文件已在 HostCat 之外被修改"
                logger.warning("检测到外部修改")
            } else {
                applyError = "hosts 未应用: \(errorMessage)"
                logger.error("\(failureLogPrefix)，hosts 未应用: \(errorMessage)")
            }
        }
    }

    private func persistDraftConfig() -> Bool {
        do {
            try configStore.save(config)
            logger.info("配置草稿持久化成功")
            return true
        } catch {
            logger.error("配置草稿持久化失败: \(error.localizedDescription)")
            applyError = "配置保存失败: \(error.localizedDescription)"
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
            logger.debug("合并预览更新: \(merged.records.count) 条记录, \(merged.duplicateCount) 条重复")
        } catch let HostMergeError.conflicts(conflicts) {
            lastConflicts = conflicts
            applyError = "检测到 \(conflicts.count) 个冲突"
            logger.warning("预览冲突: \(conflicts.count) 个")
        } catch {
            applyError = error.localizedDescription
            logger.error("预览合并失败: \(error.localizedDescription)")
        }
    }

    public func clearError() {
        applyError = nil
    }
}
