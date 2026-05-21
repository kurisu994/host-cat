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

    private let mutationService = ConfigMutationService()
    private let coordinator: HostWriteCoordinator
    private let configStore: AppConfigStore
    private let logger = Logger(subsystem: "com.hostcat.app", category: "MenuBarViewModel")

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
            mutationService.setNodeActive(
                id: id,
                active: !currentActive,
                inGroup: groupID,
                in: &config
            )
            logger.info("节点 \(config.groups[groupIndex].nodes[nodeIndex].name) 状态切换为 \(!currentActive)")
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

        Task {
            let (result, rolledBackConfig) = await coordinator.scheduleApply(config: config)

            isApplying = false

            // 如果写入失败且有回滚配置，恢复内存状态
            if !result.success, let rolledBack = rolledBackConfig {
                config = rolledBack
                logger.warning("写入失败，配置已回滚到上次成功状态")
            }

            if result.success {
                // 更新 config 中的状态
                if let hash = result.appliedHash {
                    config.state.lastAppliedHostsHash = hash
                }
                if let at = result.appliedAt {
                    config.state.lastAppliedAt = at
                }

                // 持久化配置
                do {
                    try configStore.save(config)
                    logger.info("配置持久化成功")
                } catch {
                    logger.error("配置持久化失败: \(error.localizedDescription)")
                    applyError = "配置保存失败: \(error.localizedDescription)"
                }

                // 更新合并预览
                updateMergedPreview()
            } else if let conflicts = result.conflicts {
                lastConflicts = conflicts
                applyError = "检测到 \(conflicts.count) 个冲突，请解决后再应用"
                logger.warning("合并冲突: \(conflicts.count) 个")
            } else if let errorMessage = result.errorMessage {
                applyError = errorMessage
                logger.error("应用失败: \(errorMessage)")
            }
        }
    }

    public func applyImmediately() async -> ApplyResult {
        isApplying = true
        applyError = nil
        lastConflicts = []

        let (result, rolledBackConfig) = await coordinator.applyImmediately(config: config)

        isApplying = false

        // 如果写入失败且有回滚配置，恢复内存状态
        if !result.success, let rolledBack = rolledBackConfig {
            config = rolledBack
            logger.warning("即时应用失败，配置已回滚到上次成功状态")
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
                logger.info("即时应用配置持久化成功")
            } catch {
                logger.error("即时应用配置持久化失败: \(error.localizedDescription)")
                applyError = "配置保存失败: \(error.localizedDescription)"
            }
            updateMergedPreview()
        } else if let conflicts = result.conflicts {
            lastConflicts = conflicts
            applyError = "检测到 \(conflicts.count) 个冲突，请解决后再应用"
            logger.warning("即时应用冲突: \(conflicts.count) 个")
        } else if let errorMessage = result.errorMessage {
            applyError = errorMessage
            logger.error("即时应用失败: \(errorMessage)")
        }

        return result
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
