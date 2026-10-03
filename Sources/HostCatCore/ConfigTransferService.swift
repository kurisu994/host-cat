import Foundation

/// 配置导入时的冲突处理方式。
public enum ConfigImportMode: Equatable, Sendable {
    /// 用导入内容替换默认节点内容和全部分组。
    case replace
    /// 按分组名 / 节点名匹配合并，默认节点保持不变。
    case merge
}

/// 导入结果统计，用于 UI 提示。
public struct ConfigImportSummary: Equatable, Sendable {
    public var addedGroups: Int
    public var addedNodes: Int
    public var updatedNodes: Int

    public init(addedGroups: Int = 0, addedNodes: Int = 0, updatedNodes: Int = 0) {
        self.addedGroups = addedGroups
        self.addedNodes = addedNodes
        self.updatedNodes = updatedNodes
    }
}

public struct ConfigImportResult: Equatable, Sendable {
    public var config: AppConfig
    public var summary: ConfigImportSummary
}

public enum ConfigTransferError: Error, Equatable, LocalizedError, Sendable {
    case invalidFormat
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidFormat:
            LC.transferErrorInvalidFormat
        case let .unsupportedVersion(version):
            LC.configErrorUnsupportedVersion(version)
        }
    }
}

/// 配置导入导出服务，纯逻辑，不触碰文件系统。
public struct ConfigTransferService: Sendable {
    public init() {}

    /// 导出配置 JSON。清除 `state`（hash 与应用时间），避免换机后误判外部修改。
    public func exportData(_ config: AppConfig) throws -> Data {
        var exported = config
        exported.state = AppStateMetadata()
        return try JSONEncoder.hostCatConfigEncoder.encode(exported)
    }

    /// 解码并校验导入数据：格式合法、版本受支持，并迁移到当前版本。
    public func decode(_ data: Data) throws -> AppConfig {
        let decoded: AppConfig
        do {
            decoded = try JSONDecoder.hostCatConfigDecoder.decode(AppConfig.self, from: data)
        } catch {
            throw ConfigTransferError.invalidFormat
        }
        return try migrate(decoded)
    }

    /// 旧版本迁移入口。目前只有 v1；新增版本时在此补充逐级迁移。
    private func migrate(_ config: AppConfig) throws -> AppConfig {
        guard (1...AppConfigStore.currentConfigVersion).contains(config.configVersion) else {
            throw ConfigTransferError.unsupportedVersion(config.configVersion)
        }
        var migrated = config
        migrated.configVersion = AppConfigStore.currentConfigVersion
        // 与 AppConfigStore 加载规则保持一致：默认节点恒激活，分组统一多选。
        migrated.defaultNode.isActive = true
        for index in migrated.groups.indices {
            migrated.groups[index].isSingleSelect = false
        }
        return migrated
    }

    /// 把导入配置应用到当前配置，settings 与 state 始终保留本机值。
    public func apply(_ imported: AppConfig, to current: AppConfig, mode: ConfigImportMode) -> ConfigImportResult {
        switch mode {
        case .replace:
            replace(imported, in: current)
        case .merge:
            merge(imported, into: current)
        }
    }

    private func replace(_ imported: AppConfig, in current: AppConfig) -> ConfigImportResult {
        var result = current
        result.defaultNode.content = imported.defaultNode.content
        result.groups = imported.groups
        let summary = ConfigImportSummary(
            addedGroups: imported.groups.count,
            addedNodes: imported.groups.reduce(0) { $0 + $1.nodes.count }
        )
        return ConfigImportResult(config: result, summary: summary)
    }

    private func merge(_ imported: AppConfig, into current: AppConfig) -> ConfigImportResult {
        var result = current
        var summary = ConfigImportSummary()

        for importedGroup in imported.groups {
            guard let groupIndex = result.groups.firstIndex(where: { $0.name == importedGroup.name }) else {
                // 新分组与新节点使用新 ID，避免与本机已有 ID 冲突
                var newGroup = HostGroup(name: importedGroup.name, isSingleSelect: false, nodes: [])
                newGroup.nodes = importedGroup.nodes.map(Self.freshCopy)
                result.groups.append(newGroup)
                summary.addedGroups += 1
                summary.addedNodes += newGroup.nodes.count
                continue
            }

            for importedNode in importedGroup.nodes {
                if let nodeIndex = result.groups[groupIndex].nodes.firstIndex(where: { $0.name == importedNode.name }) {
                    // 同名节点只覆盖内容，保留本机激活状态
                    // 内容相同视为无变化，不计入更新数
                    if result.groups[groupIndex].nodes[nodeIndex].content != importedNode.content {
                        result.groups[groupIndex].nodes[nodeIndex].content = importedNode.content
                        summary.updatedNodes += 1
                    }
                } else {
                    result.groups[groupIndex].nodes.append(Self.freshCopy(importedNode))
                    summary.addedNodes += 1
                }
            }
        }
        return ConfigImportResult(config: result, summary: summary)
    }

    /// 合并新增的节点一律不激活，避免导入后意外改动 hosts。
    private static func freshCopy(_ node: HostNode) -> HostNode {
        HostNode(name: node.name, content: node.content, isActive: false)
    }
}
