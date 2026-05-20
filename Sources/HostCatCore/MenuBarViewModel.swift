import Foundation

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
            guard let groupIndex = config.groups.firstIndex(where: { $0.id == groupID }) else { return }
            guard let nodeIndex = config.groups[groupIndex].nodes.firstIndex(where: { $0.id == id }) else { return }
            let currentActive = config.groups[groupIndex].nodes[nodeIndex].isActive
            mutationService.setNodeActive(
                id: id,
                active: !currentActive,
                inGroup: groupID,
                in: &config
            )
        } else {
            // 默认节点不可停用
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
            let result = await coordinator.scheduleApply(config: config)

            isApplying = false

            if result.success {
                // 更新 config 中的状态
                if let hash = result.appliedHash {
                    config.state.lastAppliedHostsHash = hash
                }
                if let at = result.appliedAt {
                    config.state.lastAppliedAt = at
                }

                // 持久化配置
                try? configStore.save(config)

                // 更新合并预览
                updateMergedPreview()
            } else if let conflicts = result.conflicts {
                lastConflicts = conflicts
                applyError = "检测到 \(conflicts.count) 个冲突，请解决后再应用"
            } else if let errorMessage = result.errorMessage {
                applyError = errorMessage
            }
        }
    }

    public func applyImmediately() async -> ApplyResult {
        isApplying = true
        applyError = nil
        lastConflicts = []

        let result = await coordinator.applyImmediately(config: config)

        isApplying = false

        if result.success {
            if let hash = result.appliedHash {
                config.state.lastAppliedHostsHash = hash
            }
            if let at = result.appliedAt {
                config.state.lastAppliedAt = at
            }
            try? configStore.save(config)
            updateMergedPreview()
        } else if let conflicts = result.conflicts {
            lastConflicts = conflicts
            applyError = "检测到 \(conflicts.count) 个冲突，请解决后再应用"
        } else if let errorMessage = result.errorMessage {
            applyError = errorMessage
        }

        return result
    }

    // MARK: - Preview

    public func updateMergedPreview() {
        do {
            let merged = try HostsMerger().merge(config)
            lastMergedText = merged.text
            lastDuplicateCount = merged.duplicateCount
        } catch let HostMergeError.conflicts(conflicts) {
            lastConflicts = conflicts
            applyError = "检测到 \(conflicts.count) 个冲突"
        } catch {
            applyError = error.localizedDescription
        }
    }

    public func clearError() {
        applyError = nil
    }
}
