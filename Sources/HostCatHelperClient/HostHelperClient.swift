import Foundation
import HostCatCore
import os.log

/// 预览模式 helper client，不真实写入 /etc/hosts。
///
/// 仅在 Debug 构建中接管 helper 调用，避免开发期需要安装 Privileged Helper。
/// 每次"写入"都会打 warning 级日志，提醒开发者本次操作并未落盘，
/// 否则日志里会看到一串假的"写入成功"，非常容易误导排错。
public struct PreviewHostHelperClient: HostHelperClient {
    private let logger = Logger(subsystem: "com.hostcat.app", category: "PreviewHostHelperClient")

    public init() {}

    public func writeHosts(
        _ contents: String,
        expectedCurrentHostsHash _: String?
    ) async throws -> HostHelperWriteResult {
        let hash = HostsHash.sha256Hex(contents)
        logger.warning(
            "[Preview] 此次写入未真正落盘到 /etc/hosts，仅返回模拟 hash=\(hash.prefix(8), privacy: .public)... 如需真实写入请用 Release 构建"
        )
        return HostHelperWriteResult(
            finalHostsHash: hash,
            didRefreshDNS: false
        )
    }
}
