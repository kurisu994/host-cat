import Foundation

public struct HostHelperWriteResult: Equatable, Sendable {
    public var finalHostsHash: String
    public var didRefreshDNS: Bool

    public init(finalHostsHash: String, didRefreshDNS: Bool) {
        self.finalHostsHash = finalHostsHash
        self.didRefreshDNS = didRefreshDNS
    }
}

/// Helper client 错误类型
public enum HostHelperClientError: Error, Equatable, LocalizedError, Sendable {
    /// Helper 暂不可用（通用原因）
    case unavailable(String)
    /// Helper 未注册
    case helperNotRegistered
    /// Helper 未在系统设置中审批
    case helperNotApproved
    /// XPC 连接中断（可能自动恢复）
    case connectionInterrupted
    /// XPC 连接永久失效
    case connectionInvalidated
    /// XPC 请求超时
    case requestTimedOut
    /// Helper 返回 hash 不匹配
    case hashMismatch
    /// Helper 返回 hosts 文件被 immutable flags 保护
    case fileImmutable
    /// Helper 返回的回复格式无法解析
    case unexpectedReply(String)

    public var errorDescription: String? {
        switch self {
        case let .unavailable(reason):
            "Privileged Helper 暂不可用：\(reason)"
        case .helperNotRegistered:
            "Privileged Helper 尚未注册，请在设置中完成注册"
        case .helperNotApproved:
            "Privileged Helper 需要在系统设置 > 登录项中批准"
        case .connectionInterrupted:
            "与 Helper 的连接中断，请重试"
        case .connectionInvalidated:
            "与 Helper 的连接已失效，请检查 Helper 状态"
        case .requestTimedOut:
            "与 Helper 通信超时，请重试"
        case .hashMismatch:
            "hosts 文件已在 HostCat 之外被修改"
        case .fileImmutable:
            "hosts 文件被锁定保护"
        case let .unexpectedReply(detail):
            "Helper 返回意外响应：\(detail)"
        }
    }
}

/// Helper client 协议，主应用通过此协议与 Helper 交互
public protocol HostHelperClient: Sendable {
    func writeHosts(_ contents: String, expectedCurrentHostsHash: String?) async throws -> HostHelperWriteResult
}

// MARK: - XPC 协议

/// XPC 层共享协议定义，Helper（服务端）和 Client（客户端）都需要引用。
/// 使用 @objc protocol + NSXPCInterface，参数限制为 XPC 稳定支持的桥接类型。
@objc public protocol HostCatHelperXPCProtocol {
    func writeHosts(
        _ contents: NSString,
        expectedCurrentHostsHash: NSString?,
        withReply reply: @escaping (NSDictionary) -> Void
    )
}
