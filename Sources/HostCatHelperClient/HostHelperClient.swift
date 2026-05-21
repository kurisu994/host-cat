import Foundation
import HostCatCore

/// 预览模式 helper client，不真实写入 /etc/hosts
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
