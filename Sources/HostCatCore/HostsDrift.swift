import Foundation

/// 启动时配置和磁盘 hosts 的关系。
public enum HostsDrift: Equatable, Sendable {
    /// 磁盘内容就是当前配置合成出的结果。
    case inSync
    /// 磁盘还是上次已知内容，但当前配置还没写进去。
    case unapplied
    /// 磁盘内容和上次已知 hash 不同，说明 HostCat 之外有人改过。
    case externallyModified
}

/// 用 hash 判断 hosts 是否和配置一致，不读取具体条目。
public enum HostsDriftChecker {
    public static func evaluate(
        diskHash: String,
        lastAppliedHostsHash: String?,
        lastExternalHostsHash: String?,
        mergedText: String?
    ) -> HostsDrift {
        if let mergedText, HostsHash.sha256Hex(mergedText) == diskHash {
            return .inSync
        }
        let baseline = lastAppliedHostsHash ?? lastExternalHostsHash
        if let baseline, diskHash != baseline {
            return .externallyModified
        }
        return .unapplied
    }
}
