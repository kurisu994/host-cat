import Foundation
import HostCatCore

public struct PreviewHostHelperClient: HostHelperClient {
    public init() {}

    public func writeHosts(
        _ contents: String,
        expectedCurrentHostsHash _: String?
    ) async throws -> HostHelperWriteResult {
        HostHelperWriteResult(
            finalHostsHash: HostsHash.sha256Hex(contents),
            didRefreshDNS: false
        )
    }
}

@objc public protocol HostCatHelperXPCProtocol {
    func writeHosts(
        _ contents: NSString,
        expectedCurrentHostsHash: NSString?,
        withReply reply: @escaping (NSDictionary) -> Void
    )
}
