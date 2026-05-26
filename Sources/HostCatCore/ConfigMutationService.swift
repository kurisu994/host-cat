import Foundation
import os.log

public enum MoveDirection: Sendable {
    case up
    case down
}

/// Result of a configuration mutation operation.
public enum MutationResult: Equatable, Sendable {
    case success
    case notFound
}

public struct ConfigMutationService: Sendable {
    private let logger = Logger(subsystem: "com.hostcat.app", category: "ConfigMutation")

    public init() {}

    // MARK: - Group Operations

    public func addGroup(named name: String, to config: inout AppConfig) {
        let group = HostGroup(name: name, isSingleSelect: false, nodes: [])
        config.groups.append(group)
        logger.info("Added group: \(name)")
    }

    @discardableResult
    public func removeGroup(id: UUID, from config: inout AppConfig) -> MutationResult {
        let originalCount = config.groups.count
        config.groups.removeAll { $0.id == id }
        guard config.groups.count < originalCount else {
            logger.warning("Failed to remove group, ID not found: \(id.uuidString)")
            return .notFound
        }
        logger.info("Removed group: \(id.uuidString)")
        return .success
    }

    @discardableResult
    public func renameGroup(id: UUID, to name: String, in config: inout AppConfig) -> MutationResult {
        guard let index = config.groups.firstIndex(where: { $0.id == id }) else {
            logger.warning("Failed to rename group, ID not found: \(id.uuidString)")
            return .notFound
        }
        let oldName = config.groups[index].name
        config.groups[index].name = name
        logger.info("Group renamed: \(oldName) -> \(name)")
        return .success
    }

    @discardableResult
    public func moveGroup(id: UUID, direction: MoveDirection, in config: inout AppConfig) -> MutationResult {
        guard let index = config.groups.firstIndex(where: { $0.id == id }) else {
            logger.warning("Failed to move group, ID not found: \(id.uuidString)")
            return .notFound
        }
        let targetIndex: Int
        switch direction {
        case .up:
            guard index > 0 else {
                logger.debug("Group already at top, cannot move up")
                return .success
            }
            targetIndex = index - 1
        case .down:
            guard index < config.groups.count - 1 else {
                logger.debug("Group already at bottom, cannot move down")
                return .success
            }
            targetIndex = index + 1
        }
        config.groups.swapAt(index, targetIndex)
        let movedGroupName = config.groups[targetIndex].name
        logger.info("Group moved: \(movedGroupName)")
        return .success
    }

    @discardableResult
    public func setGroupSingleSelect(_ isSingleSelect: Bool, forGroup groupID: UUID, in config: inout AppConfig) -> MutationResult {
        guard let index = config.groups.firstIndex(where: { $0.id == groupID }) else {
            logger.warning("Failed to set single/multi select, group not found: \(groupID.uuidString)")
            return .notFound
        }
        config.groups[index].isSingleSelect = isSingleSelect
        let groupName = config.groups[index].name
        let modeName = isSingleSelect ? "single" : "multi"
        logger.info("Group \(groupName) switched to \(modeName) select")
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
            logger.warning("Failed to add node, group not found: \(groupID.uuidString)")
            return .notFound
        }
        let node = HostNode(name: name, content: content, isActive: false)
        config.groups[index].nodes.append(node)
        let groupName = config.groups[index].name
        logger.info("Added node \(name) to group \(groupName)")
        return .success
    }

    @discardableResult
    public func removeNode(
        id: UUID,
        fromGroup groupID: UUID,
        in config: inout AppConfig
    ) -> MutationResult {
        guard let groupIndex = config.groups.firstIndex(where: { $0.id == groupID }) else {
            logger.warning("Failed to remove node, group not found: \(groupID.uuidString)")
            return .notFound
        }
        let originalCount = config.groups[groupIndex].nodes.count
        config.groups[groupIndex].nodes.removeAll { $0.id == id }
        guard config.groups[groupIndex].nodes.count < originalCount else {
            logger.warning("Failed to remove node, node not found: \(id.uuidString)")
            return .notFound
        }
        logger.info("Removed node: \(id.uuidString)")
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
            logger.warning("Failed to rename node, group not found: \(groupID.uuidString)")
            return .notFound
        }
        guard let nodeIndex = config.groups[groupIndex].nodes.firstIndex(where: { $0.id == id }) else {
            logger.warning("Failed to rename node, node not found: \(id.uuidString)")
            return .notFound
        }
        let oldName = config.groups[groupIndex].nodes[nodeIndex].name
        config.groups[groupIndex].nodes[nodeIndex].name = name
        logger.info("Node renamed: \(oldName) -> \(name)")
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
            logger.warning("Failed to move node, group not found: \(groupID.uuidString)")
            return .notFound
        }
        guard let nodeIndex = config.groups[groupIndex].nodes.firstIndex(where: { $0.id == id }) else {
            logger.warning("Failed to move node, node not found: \(id.uuidString)")
            return .notFound
        }

        let targetIndex: Int
        switch direction {
        case .up:
            guard nodeIndex > 0 else {
                logger.debug("Node already at top, cannot move up")
                return .success
            }
            targetIndex = nodeIndex - 1
        case .down:
            guard nodeIndex < config.groups[groupIndex].nodes.count - 1 else {
                logger.debug("Node already at bottom, cannot move down")
                return .success
            }
            targetIndex = nodeIndex + 1
        }
        config.groups[groupIndex].nodes.swapAt(nodeIndex, targetIndex)
        let movedNodeName = config.groups[groupIndex].nodes[targetIndex].name
        logger.info("Node moved: \(movedNodeName)")
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
            logger.warning("Failed to update node content, group not found: \(groupID.uuidString)")
            return .notFound
        }
        guard let nodeIndex = config.groups[groupIndex].nodes.firstIndex(where: { $0.id == id }) else {
            logger.warning("Failed to update node content, node not found: \(id.uuidString)")
            return .notFound
        }
        config.groups[groupIndex].nodes[nodeIndex].content = content
        let nodeName = config.groups[groupIndex].nodes[nodeIndex].name
        logger.info("Updated node \(nodeName) content")
        return .success
    }

    // MARK: - Default Node Operations

    public func renameDefaultNode(to name: String, in config: inout AppConfig) {
        let oldName = config.defaultNode.name
        config.defaultNode.name = name
        logger.info("Default node renamed: \(oldName) -> \(name)")
    }

    public func updateDefaultNodeContent(_ content: String, in config: inout AppConfig) {
        config.defaultNode.content = content
        logger.info("Updated default node content")
    }

    public func removeDefaultNode(from config: inout AppConfig) {
        // Default node cannot be removed; this operation has no effect.
        logger.debug("Attempted to remove default node, ignored")
    }

    public func setDefaultNodeActive(_ isActive: Bool, in config: inout AppConfig) {
        // Default node is always active and cannot be deactivated.
        if !isActive {
            logger.debug("Attempted to deactivate default node, ignored")
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
            logger.warning("Failed to activate node, group not found: \(groupID.uuidString)")
            return .notFound
        }
        guard let nodeIndex = config.groups[groupIndex].nodes.firstIndex(where: { $0.id == id }) else {
            logger.warning("Failed to activate node, node not found: \(id.uuidString)")
            return .notFound
        }

        config.groups[groupIndex].nodes[nodeIndex].isActive = active
        let nodeName = config.groups[groupIndex].nodes[nodeIndex].name
        logger.info("Node \(nodeName) status set to \(active)")
        return .success
    }
}
