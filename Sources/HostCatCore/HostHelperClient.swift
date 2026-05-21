import Foundation

public struct HostHelperWriteResult: Equatable, Sendable {
    public var finalHostsHash: String
    public var didRefreshDNS: Bool

    public init(finalHostsHash: String, didRefreshDNS: Bool) {
        self.finalHostsHash = finalHostsHash
        self.didRefreshDNS = didRefreshDNS
    }
}

public enum HostHelperClientError: Error, Equatable, LocalizedError, Sendable {
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case let .unavailable(reason):
            "Privileged Helper 暂不可用：\(reason)"
        }
    }
}

public protocol HostHelperClient: Sendable {
    func writeHosts(_ contents: String, expectedCurrentHostsHash: String?) async throws -> HostHelperWriteResult
}
