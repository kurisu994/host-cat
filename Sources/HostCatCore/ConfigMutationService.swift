import Foundation
import os.log

public enum MoveDirection: Sendable {
    case up
    case down
}

/// 配置变更操作结果
public enum MutationResult: Equatable, Sendable {
    case success
    case notFound
}

public struct ConfigMutationService: Sendable {
    private let logger = Logger(subsystem: "com.hostcat.app", category: "ConfigMutation")

    public init() {}

    // MARK: - Group Operations

    public func addGroup(named name: String, to config: inout AppConfig) {
        let group = HostGroup(name: name, isSingleSelect: true, nodes: [])
        config.groups.append(group)
        logger.info("添加分组: \(name)")
    }

    @discardableResult
    public func removeGroup(id: UUID, from config: inout AppConfig) -> MutationResult {
        let originalCount = config.groups.count
        config.groups.removeAll { $0.id == id }
        guard config.groups.count < originalCount else {
            logger.warning("删除分组失败，ID 不存在: \(id.uuidString)")
            return .notFound
        }
        logger.info("删除分组: \(id.uuidString)")
        return .success
    }

    @discardableResult
    public func renameGroup(id: UUID, to name: String, in config: inout AppConfig) -> MutationResult {
        guard let index = config.groups.firstIndex(where: { $0.id == id }) else {
            logger.warning("重命名分组失败，ID 不存在: \(id.uuidString)")
            return .notFound
        }
        let oldName = config.groups[index].name
        config.groups[index].name = name
        logger.info("分组重命名: \(oldName) -> \(name)")
        return .success
    }

    @discardableResult
    public func moveGroup(id: UUID, direction: MoveDirection, in config: inout AppConfig) -> MutationResult {
        guard let index = config.groups.firstIndex(where: { $0.id == id }) else {
            logger.warning("移动分组失败，ID 不存在: \(id.uuidString)")
            return .notFound
        }
        let targetIndex: Int
        switch direction {
        case .up:
            guard index > 0 else {
                logger.debug("分组已在最顶部，无法上移")
                return .success
            }
            targetIndex = index - 1
        case .down:
            guard index < config.groups.count - 1 else {
                logger.debug("分组已在最底部，无法下移")
                return .success
            }
            targetIndex = index + 1
        }
        config.groups.swapAt(index, targetIndex)
        logger.info("分组移动: \(config.groups[targetIndex].name)")
        return .success
    }

    @discardableResult
    public func setGroupSingleSelect(_ isSingleSelect: Bool, forGroup groupID: UUID, in config: inout AppConfig) -> MutationResult {
        guard let index = config.groups.firstIndex(where: { $0.id == groupID }) else {
            logger.warning("设置单选/多选失败，分组不存在: \(groupID.uuidString)")
            return .notFound
        }
        config.groups[index].isSingleSelect = isSingleSelect
        logger.info("分组 \(config.groups[index].name) 切换为 \(isSingleSelect ? "单选" : "多选")")
        return .success
    }

    // MARK: - Node Operations (within a group)

    @discardableResult
    public func addNode(
        named name: String,
        content: String,
        toGroup groupID: UUID,
        in config: inout AppConfig
    ) -> MutationResult {
        guard let index = config.groups.firstIndex(where: { $0.id == groupID }) else {
            logger.warning("添加节点失败，分组不存在: \(groupID.uuidString)")
            return .notFound
        }
        let node = HostNode(name: name, content: content, isActive: false)
        config.groups[index].nodes.append(node)
        logger.info("添加节点 \(name) 到分组 \(config.groups[index].name)")
        return .success
    }

    @discardableResult
    public func removeNode(
        id: UUID,
        fromGroup groupID: UUID,
        in config: inout AppConfig
    ) -> MutationResult {
        guard let groupIndex = config.groups.firstIndex(where: { $0.id == groupID }) else {
            logger.warning("删除节点失败，分组不存在: \(groupID.uuidString)")
            return .notFound
        }
        let originalCount = config.groups[groupIndex].nodes.count
        config.groups[groupIndex].nodes.removeAll { $0.id == id }
        guard config.groups[groupIndex].nodes.count < originalCount else {
            logger.warning("删除节点失败，节点不存在: \(id.uuidString)")
            return .notFound
        }
        logger.info("删除节点: \(id.uuidString)")
        return .success
    }

    @discardableResult
    public func renameNode(
        id: UUID,
        to name: String,
        inGroup groupID: UUID,
        in config: inout AppConfig
    ) -> MutationResult {
        guard let groupIndex = config.groups.firstIndex(where: { $0.id == groupID }) else {
            logger.warning("重命名节点失败，分组不存在: \(groupID.uuidString)")
            return .notFound
        }
        guard let nodeIndex = config.groups[groupIndex].nodes.firstIndex(where: { $0.id == id }) else {
            logger.warning("重命名节点失败，节点不存在: \(id.uuidString)")
            return .notFound
        }
        let oldName = config.groups[groupIndex].nodes[nodeIndex].name
        config.groups[groupIndex].nodes[nodeIndex].name = name
        logger.info("节点重命名: \(oldName) -> \(name)")
        return .success
    }

    @discardableResult
    public func moveNode(
        id: UUID,
        direction: MoveDirection,
        inGroup groupID: UUID,
        in config: inout AppConfig
    ) -> MutationResult {
        guard let groupIndex = config.groups.firstIndex(where: { $0.id == groupID }) else {
            logger.warning("移动节点失败，分组不存在: \(groupID.uuidString)")
            return .notFound
        }
        guard let nodeIndex = config.groups[groupIndex].nodes.firstIndex(where: { $0.id == id }) else {
            logger.warning("移动节点失败，节点不存在: \(id.uuidString)")
            return .notFound
        }

        let targetIndex: Int
        switch direction {
        case .up:
            guard nodeIndex > 0 else {
                logger.debug("节点已在最顶部，无法上移")
                return .success
            }
            targetIndex = nodeIndex - 1
        case .down:
            guard nodeIndex < config.groups[groupIndex].nodes.count - 1 else {
                logger.debug("节点已在最底部，无法下移")
                return .success
            }
            targetIndex = nodeIndex + 1
        }
        config.groups[groupIndex].nodes.swapAt(nodeIndex, targetIndex)
        logger.info("节点移动: \(config.groups[groupIndex].nodes[targetIndex].name)")
        return .success
    }

    @discardableResult
    public func updateNodeContent(
        id: UUID,
        content: String,
        inGroup groupID: UUID,
        in config: inout AppConfig
    ) -> MutationResult {
        guard let groupIndex = config.groups.firstIndex(where: { $0.id == groupID }) else {
            logger.warning("更新节点内容失败，分组不存在: \(groupID.uuidString)")
            return .notFound
        }
        guard let nodeIndex = config.groups[groupIndex].nodes.firstIndex(where: { $0.id == id }) else {
            logger.warning("更新节点内容失败，节点不存在: \(id.uuidString)")
            return .notFound
        }
        config.groups[groupIndex].nodes[nodeIndex].content = content
        logger.info("更新节点 \(config.groups[groupIndex].nodes[nodeIndex].name) 内容")
        return .success
    }

    // MARK: - Default Node Operations

    public func renameDefaultNode(to name: String, in config: inout AppConfig) {
        let oldName = config.defaultNode.name
        config.defaultNode.name = name
        logger.info("默认节点重命名: \(oldName) -> \(name)")
    }

    public func updateDefaultNodeContent(_ content: String, in config: inout AppConfig) {
        config.defaultNode.content = content
        logger.info("更新默认节点内容")
    }

    public func removeDefaultNode(from config: inout AppConfig) {
        // 默认节点不可删除，此操作无效果
        logger.debug("尝试删除默认节点，已忽略")
    }

    public func setDefaultNodeActive(_ isActive: Bool, in config: inout AppConfig) {
        // 默认节点始终激活，不可停用
        if !isActive {
            logger.debug("尝试停用默认节点，已忽略")
        }
        config.defaultNode.isActive = true
    }

    // MARK: - Node Activation

    @discardableResult
    public func setNodeActive(
        id: UUID,
        active: Bool,
        inGroup groupID: UUID,
        in config: inout AppConfig
    ) -> MutationResult {
        guard let groupIndex = config.groups.firstIndex(where: { $0.id == groupID }) else {
            logger.warning("激活节点失败，分组不存在: \(groupID.uuidString)")
            return .notFound
        }
        guard let nodeIndex = config.groups[groupIndex].nodes.firstIndex(where: { $0.id == id }) else {
            logger.warning("激活节点失败，节点不存在: \(id.uuidString)")
            return .notFound
        }

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
        logger.info("节点 \(config.groups[groupIndex].nodes[nodeIndex].name) 状态设为 \(active)")
        return .success
    }
}
