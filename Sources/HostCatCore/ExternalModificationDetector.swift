import Foundation

/// 外部修改检测结果
public enum ExternalModificationResult: Equatable, Sendable {
    /// 没有变化，hash 匹配
    case noChange
    /// 文件已被外部修改（hash 不匹配）
    case modified
    /// 首次运行，没有预期 hash
    case firstRun
}

/// 检测 /etc/hosts 是否在 HostCat 之外被修改
public struct ExternalModificationDetector: Sendable {
    public init() {}

    /// 检测当前 hosts 内容与预期 hash 是否一致
    ///
    /// - Parameters:
    ///   - expectedHash: 上次 HostCat 成功写入后记录的 hash，nil 表示首次运行
    ///   - currentHostsContent: 当前 /etc/hosts 的文本内容
    /// - Returns: 检测结果
    public func detect(
        expectedHash: String?,
        currentHostsContent: String
    ) -> ExternalModificationResult {
        guard let expectedHash, !expectedHash.isEmpty else {
            return .firstRun
        }

        let currentHash = HostsHash.sha256Hex(currentHostsContent)
        if currentHash == expectedHash {
            return .noChange
        }

        return .modified
    }
}
