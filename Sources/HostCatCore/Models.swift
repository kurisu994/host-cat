import Foundation

public struct AppConfig: Codable, Equatable, Sendable {
    public var configVersion: Int
    public var defaultNode: HostNode
    public var groups: [HostGroup]
    public var settings: AppSettings
    public var state: AppStateMetadata

    public init(
        configVersion: Int,
        defaultNode: HostNode,
        groups: [HostGroup],
        settings: AppSettings,
        state: AppStateMetadata
    ) {
        self.configVersion = configVersion
        self.defaultNode = defaultNode
        self.groups = groups
        self.settings = settings
        self.state = state
    }

    public static func initial(defaultHosts: String) -> AppConfig {
        AppConfig(
            configVersion: 1,
            defaultNode: HostNode(name: "默认", content: defaultHosts, isActive: true),
            groups: [],
            settings: AppSettings(launchAtLogin: false),
            state: AppStateMetadata()
        )
    }
}

public struct HostGroup: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var isSingleSelect: Bool
    public var nodes: [HostNode]

    public init(
        id: UUID = UUID(),
        name: String,
        isSingleSelect: Bool = true,
        nodes: [HostNode] = []
    ) {
        self.id = id
        self.name = name
        self.isSingleSelect = isSingleSelect
        self.nodes = nodes
    }
}

public struct HostNode: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var content: String
    public var isActive: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        content: String,
        isActive: Bool
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.isActive = isActive
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var launchAtLogin: Bool

    public init(launchAtLogin: Bool) {
        self.launchAtLogin = launchAtLogin
    }
}

public struct AppStateMetadata: Codable, Equatable, Sendable {
    public var lastAppliedHostsHash: String?
    public var lastAppliedAt: Date?

    public init(
        lastAppliedHostsHash: String? = nil,
        lastAppliedAt: Date? = nil
    ) {
        self.lastAppliedHostsHash = lastAppliedHostsHash
        self.lastAppliedAt = lastAppliedAt
    }
}
