import Foundation

public enum MoveDirection: Sendable {
    case up
    case down
}

public struct ConfigMutationService: Sendable {
    public init() {}

    // MARK: - Group Operations

    public func addGroup(named name: String, to config: inout AppConfig) {
        let group = HostGroup(name: name, isSingleSelect: true, nodes: [])
        config.groups.append(group)
    }

    public func removeGroup(id: UUID, from config: inout AppConfig) {
        config.groups.removeAll { $0.id == id }
    }

    public func renameGroup(id: UUID, to name: String, in config: inout AppConfig) {
        guard let index = config.groups.firstIndex(where: { $0.id == id }) else { return }
        config.groups[index].name = name
    }

    public func moveGroup(id: UUID, direction: MoveDirection, in config: inout AppConfig) {
        guard let index = config.groups.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex: Int
        switch direction {
        case .up:
            guard index > 0 else { return }
            targetIndex = index - 1
        case .down:
            guard index < config.groups.count - 1 else { return }
            targetIndex = index + 1
        }
        config.groups.swapAt(index, targetIndex)
    }

    public func setGroupSingleSelect(_ isSingleSelect: Bool, forGroup groupID: UUID, in config: inout AppConfig) {
        guard let index = config.groups.firstIndex(where: { $0.id == groupID }) else { return }
        config.groups[index].isSingleSelect = isSingleSelect
    }

    // MARK: - Node Operations (within a group)

    public func addNode(
        named name: String,
        content: String,
        toGroup groupID: UUID,
        in config: inout AppConfig
    ) {
        guard let index = config.groups.firstIndex(where: { $0.id == groupID }) else { return }
        let node = HostNode(name: name, content: content, isActive: false)
        config.groups[index].nodes.append(node)
    }

    public func removeNode(
        id: UUID,
        fromGroup groupID: UUID,
        in config: inout AppConfig
    ) {
        guard let groupIndex = config.groups.firstIndex(where: { $0.id == groupID }) else { return }
        config.groups[groupIndex].nodes.removeAll { $0.id == id }
    }

    public func renameNode(
        id: UUID,
        to name: String,
        inGroup groupID: UUID,
        in config: inout AppConfig
    ) {
        guard let groupIndex = config.groups.firstIndex(where: { $0.id == groupID }) else { return }
        guard let nodeIndex = config.groups[groupIndex].nodes.firstIndex(where: { $0.id == id }) else { return }
        config.groups[groupIndex].nodes[nodeIndex].name = name
    }

    public func moveNode(
        id: UUID,
        direction: MoveDirection,
        inGroup groupID: UUID,
        in config: inout AppConfig
    ) {
        guard let groupIndex = config.groups.firstIndex(where: { $0.id == groupID }) else { return }
        guard let nodeIndex = config.groups[groupIndex].nodes.firstIndex(where: { $0.id == id }) else { return }

        let targetIndex: Int
        switch direction {
        case .up:
            guard nodeIndex > 0 else { return }
            targetIndex = nodeIndex - 1
        case .down:
            guard nodeIndex < config.groups[groupIndex].nodes.count - 1 else { return }
            targetIndex = nodeIndex + 1
        }
        config.groups[groupIndex].nodes.swapAt(nodeIndex, targetIndex)
    }

    public func updateNodeContent(
        id: UUID,
        content: String,
        inGroup groupID: UUID,
        in config: inout AppConfig
    ) {
        guard let groupIndex = config.groups.firstIndex(where: { $0.id == groupID }) else { return }
        guard let nodeIndex = config.groups[groupIndex].nodes.firstIndex(where: { $0.id == id }) else { return }
        config.groups[groupIndex].nodes[nodeIndex].content = content
    }

    // MARK: - Default Node Operations

    public func renameDefaultNode(to name: String, in config: inout AppConfig) {
        config.defaultNode.name = name
    }

    public func updateDefaultNodeContent(_ content: String, in config: inout AppConfig) {
        config.defaultNode.content = content
    }

    public func removeDefaultNode(from config: inout AppConfig) {
        // 默认节点不可删除，此操作无效果
    }

    public func setDefaultNodeActive(_ isActive: Bool, in config: inout AppConfig) {
        // 默认节点始终激活，不可停用
        config.defaultNode.isActive = true
    }

    // MARK: - Node Activation

    public func setNodeActive(
        id: UUID,
        active: Bool,
        inGroup groupID: UUID,
        in config: inout AppConfig
    ) {
        guard let groupIndex = config.groups.firstIndex(where: { $0.id == groupID }) else { return }
        guard let nodeIndex = config.groups[groupIndex].nodes.firstIndex(where: { $0.id == id }) else { return }

        let isSingleSelect = config.groups[groupIndex].isSingleSelect

        if isSingleSelect {
            if active {
                // 单选组：激活一个时自动关闭同组其他节点
                for i in config.groups[groupIndex].nodes.indices {
                    config.groups[groupIndex].nodes[i].isActive = (i == nodeIndex)
                }
            } else {
                // 单选组：允许停用当前激活的节点
                config.groups[groupIndex].nodes[nodeIndex].isActive = false
            }
        } else {
            // 多选组：直接设置目标节点状态
            config.groups[groupIndex].nodes[nodeIndex].isActive = active
        }
    }
}
