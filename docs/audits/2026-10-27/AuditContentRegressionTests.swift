import Foundation
import XCTest
@testable import HostCatCore

/// 发布审查中的文本、备份快照回归；所有文件仅位于独立临时目录。
final class AuditContentRegressionTests: XCTestCase {
    private let systemHosts = "127.0.0.1 localhost\n255.255.255.255 broadcasthost\n::1 localhost\n"

    /// LF 对照组，确保回归不是断言或 fixture 本身有误。
    func testLFCommentPreservesFollowingRecord() throws {
        let records = try HostsParser().parse("# imported\n10.0.0.1 api.audit.test\n")
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.hostnames, ["api.audit.test"])
    }

    /// CRLF 应与 LF 具有同样的解析语义。
    func testCRLFCommentPreservesFollowingRecord() throws {
        let records = try HostsParser().parse("# imported\r\n10.0.0.1 api.audit.test\r\n")
        XCTAssertEqual(records.count, 1, "不能把整个 CRLF 节点当成首行注释")
        XCTAssertEqual(records.first?.hostnames, ["api.audit.test"])
    }

    /// 系统条目完整不能掩盖另一个 CRLF 节点的静默丢失。
    func testMergePreservesCRLFActiveNode() throws {
        var config = AppConfig.initial(defaultHosts: systemHosts)
        config.groups = [HostGroup(name: "审查", nodes: [
            HostNode(name: "CRLF", content: "# imported\r\n10.0.0.1 api.audit.test\r\n", isActive: true)
        ])]
        let merged = try HostsMerger().merge(config)
        XCTAssertNoThrow(try HostsContentValidator().validate(merged.text))
        XCTAssertTrue(merged.text.contains("10.0.0.1 api.audit.test"), "Helper 校验通过时仍可能丢失节点映射")
    }

    /// 同一 IPv6 的展开与压缩表示不能被误认为不同地址。
    func testEquivalentIPv6DoesNotConflict() throws {
        var config = AppConfig.initial(defaultHosts: systemHosts)
        config.groups = [HostGroup(name: "审查", nodes: [
            HostNode(name: "compressed", content: "2001:db8::1 api.audit.test\n", isActive: true),
            HostNode(name: "expanded", content: "2001:0db8:0:0:0:0:0:1 api.audit.test\n", isActive: true)
        ])]
        let merged = try HostsMerger().merge(config)
        XCTAssertEqual(merged.duplicateCount, 1)
    }

    /// 展开形式的 IPv6 loopback 也满足系统必备条目。
    func testExpandedLoopbackSatisfiesRequiredEntry() throws {
        let config = AppConfig.initial(defaultHosts: systemHosts.replacingOccurrences(of: "::1", with: "0:0:0:0:0:0:0:1"))
        let merged = try HostsMerger().merge(config)
        XCTAssertNoThrow(try HostsContentValidator().validate(merged.text))
    }

    /// 强制覆盖也应以本次已备份的快照作为比较前提。
    func testForceApplyProtectsChangesAfterBackup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HostCat-ForceAudit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let hostsURL = directory.appendingPathComponent("hosts-fixture")
        try systemHosts.write(to: hostsURL, atomically: true, encoding: .utf8)
        let backups = BackupStore(backupDirectory: directory.appendingPathComponent("backups"))
        let externalText = systemHosts + "10.0.0.2 external.audit.test\n"
        let helper = AuditPostBackupMutationHelper(hostsURL: hostsURL, externalText: externalText)
        let coordinator = HostWriteCoordinator(helperClient: helper, backupStore: backups, hostsPath: hostsURL.path)
        var config = AppConfig.initial(defaultHosts: systemHosts, currentHostsHash: HostsHash.sha256Hex(systemHosts))
        config.defaultNode.content += "10.0.0.3 desired.audit.test\n"
        let result = await coordinator.applyImmediately(config: config, force: true)
        XCTAssertEqual(backups.listBackups().count, 1)
        XCTAssertEqual(backups.listBackups().first.flatMap { backups.readBackup(at: $0) }, systemHosts)
        XCTAssertFalse(result.success, "备份完成后发生的新外部修改应阻止覆盖")
        XCTAssertEqual(try String(contentsOf: hostsURL, encoding: .utf8), externalText)
    }

    /// 非 UI 的万条映射冒烟测试；仅记录耗时，不设置依赖机器性能的脆弱门槛。
    func testTenThousandRecordsRoundTrip() throws {
        let content = systemHosts + (0..<10_000).map { "10.0.0.1 host\($0).audit.test" }.joined(separator: "\n") + "\n"
        let config = AppConfig.initial(defaultHosts: content)
        let start = Date()
        let merged = try HostsMerger().merge(config)
        XCTAssertEqual(merged.records.count, 10_003)
        try HostsContentValidator().validate(merged.text)
        let imported = HostsImporter().importHosts(merged.text)
        XCTAssertEqual(try HostsParser().parse(imported.safeDefaultNodeContent).count, 10_003)
        print("AUDIT_10000_RECORDS_SECONDS=\(Date().timeIntervalSince(start))")
    }
}

/// 在 coordinator 完成备份、调用 Helper 时模拟外部修改，仅操作测试自建文件。
private actor AuditPostBackupMutationHelper: HostHelperClient {
    let hostsURL: URL
    let externalText: String

    init(hostsURL: URL, externalText: String) {
        self.hostsURL = hostsURL
        self.externalText = externalText
    }

    func writeHosts(_ contents: String, expectedCurrentHostsHash: String?) async throws -> HostHelperWriteResult {
        try externalText.write(to: hostsURL, atomically: true, encoding: .utf8)
        if let expectedCurrentHostsHash, expectedCurrentHostsHash != HostsHash.sha256Hex(externalText) {
            throw HostHelperClientError.hashMismatch
        }
        try contents.write(to: hostsURL, atomically: true, encoding: .utf8)
        return HostHelperWriteResult(finalHostsHash: HostsHash.sha256Hex(contents), didRefreshDNS: true)
    }
}
