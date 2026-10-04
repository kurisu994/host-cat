import Foundation

public struct HostHelperWriteResult: Equatable, Sendable {
    public var finalHostsHash: String
    /// true 已刷新，false 刷新失败，nil 表示这次写入没有尝试刷新。
    public var didRefreshDNS: Bool?

    public init(finalHostsHash: String, didRefreshDNS: Bool? = true) {
        self.finalHostsHash = finalHostsHash
        self.didRefreshDNS = didRefreshDNS
    }
}

/// Error type for the Helper client.
public enum HostHelperClientError: Error, Equatable, LocalizedError, Sendable {
    /// Helper temporarily unavailable (generic reason).
    case unavailable(String)
    /// Helper is not registered.
    case helperNotRegistered
    /// Helper has not been approved in System Settings.
    case helperNotApproved
    /// XPC connection interrupted (may auto-recover).
    case connectionInterrupted
    /// XPC connection permanently invalidated.
    case connectionInvalidated
    /// XPC request timed out.
    case requestTimedOut
    /// Helper reported hash mismatch.
    case hashMismatch
    /// Helper reported hosts file is protected by immutable flags.
    case fileImmutable
    /// Helper returned a response that could not be parsed.
    case unexpectedReply(String)
    /// Helper 拒绝了这次写入（路径不对，或非强制写入缺少 hash）。
    case writeRejected(String)

    public var errorDescription: String? {
        switch self {
        case let .unavailable(reason):
            LC.helperUnavailable(reason)
        case .helperNotRegistered:
            LC.helperNotRegistered
        case .helperNotApproved:
            LC.helperRequiresApproval
        case .connectionInterrupted:
            LC.helperConnectionInterrupted
        case .connectionInvalidated:
            LC.helperConnectionInvalidated
        case .requestTimedOut:
            LC.helperRequestTimedOut
        case .hashMismatch:
            LC.writeErrorHashMismatch
        case .fileImmutable:
            LC.writeErrorFileImmutable
        case let .unexpectedReply(detail):
            LC.helperUnexpectedReply(detail)
        case let .writeRejected(reason):
            reason
        }
    }
}

/// Protocol for the Helper client; the main app communicates with the Helper through this protocol.
public protocol HostHelperClient: Sendable {
    func writeHosts(
        _ contents: String,
        expectedCurrentHostsHash: String?,
        force: Bool
    ) async throws -> HostHelperWriteResult
}

// MARK: - XPC Protocol

/// Shared XPC protocol definition used by both the Helper (server) and Client.
/// Uses @objc protocol + NSXPCInterface; parameters are limited to XPC-stable bridged types.
@objc public protocol HostCatHelperXPCProtocol {
    func writeHosts(
        _ contents: NSString,
        expectedCurrentHostsHash: NSString?,
        force: Bool,
        localizationIdentifier: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    )
}
