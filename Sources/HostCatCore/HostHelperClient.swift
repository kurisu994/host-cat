import Foundation

public struct HostHelperWriteResult: Equatable, Sendable {
    public var finalHostsHash: String
    public var didRefreshDNS: Bool

    public init(finalHostsHash: String, didRefreshDNS: Bool) {
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

    public var errorDescription: String? {
        switch self {
        case let .unavailable(reason):
            "Privileged Helper temporarily unavailable: \(reason)"
        case .helperNotRegistered:
            "Privileged Helper not registered. Please register in Settings."
        case .helperNotApproved:
            "Privileged Helper needs approval in System Settings > Login Items."
        case .connectionInterrupted:
            "Connection to Helper interrupted. Please retry."
        case .connectionInvalidated:
            "Connection to Helper invalidated. Please check Helper status."
        case .requestTimedOut:
            "Communication with Helper timed out. Please retry."
        case .hashMismatch:
            "hosts file has been modified outside HostCat."
        case .fileImmutable:
            "hosts file is protected by immutable flags."
        case let .unexpectedReply(detail):
            "Helper returned unexpected response: \(detail)"
        }
    }
}

/// Protocol for the Helper client; the main app communicates with the Helper through this protocol.
public protocol HostHelperClient: Sendable {
    func writeHosts(_ contents: String, expectedCurrentHostsHash: String?) async throws -> HostHelperWriteResult
}

// MARK: - XPC Protocol

/// Shared XPC protocol definition used by both the Helper (server) and Client.
/// Uses @objc protocol + NSXPCInterface; parameters are limited to XPC-stable bridged types.
@objc public protocol HostCatHelperXPCProtocol {
    func writeHosts(
        _ contents: NSString,
        expectedCurrentHostsHash: NSString?,
        withReply reply: @escaping (NSDictionary) -> Void
    )
}
