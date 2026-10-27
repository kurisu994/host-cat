import XCTest
@testable import HostCatCore

final class HostsMergerTests: XCTestCase {
    /// 合并双方实现后，原文保全与 IPv6 去重须共存，输出记录也不能丢失节点来源。
    func testDocumentPreservationAndIPv6DeduplicationKeepRecordSources() throws {
        var config = AppConfig.initial(defaultHosts: "# 默认注释\r\n\r\n2001:0DB8::1\tapi.test  # 首条\r\n")
        config.groups = [HostGroup(name: "项目", nodes: [
            HostNode(name: "开发", content: "# 节点注释\r\n\r\n2001:db8:0:0:0:0:0:1 API.TEST alias.test # 别名\r\n10.0.0.1\tother.test  # 原格式\r\n", isActive: true)
        ])]

        let merged = try HostsMerger().merge(config)
        XCTAssertTrue(merged.text.contains("# 默认注释\n\n2001:0DB8::1\tapi.test  # 首条\n"))
        XCTAssertTrue(merged.text.contains("# 节点注释\n\n2001:db8:0:0:0:0:0:1 alias.test # 别名\n"))
        XCTAssertTrue(merged.text.contains("10.0.0.1\tother.test  # 原格式\n"))
        XCTAssertEqual(merged.duplicateCount, 1)
        XCTAssertEqual(merged.records.map(\.hostnames), [["api.test"], ["alias.test"], ["other.test"]])
        XCTAssertEqual(merged.records.map(\.source), [
            HostRecordSource(nodeName: config.defaultNode.name),
            HostRecordSource(groupName: "项目", nodeName: "开发"),
            HostRecordSource(groupName: "项目", nodeName: "开发")
        ])
    }

    /// CRLF 激活节点不能在最终写入校验通过的同时丢失映射。
    func testCRLFActiveNodeSurvivesMergeAndWriteValidation() throws {
        var config = AppConfig.initial(defaultHosts: "127.0.0.1 localhost\n255.255.255.255 broadcasthost\n::1 localhost\n")
        config.groups = [HostGroup(name: "项目", nodes: [
            HostNode(name: "Windows", content: "# imported\r\n10.0.0.1 api.test\r\n", isActive: true)
        ])]

        let merged = try HostsMerger().merge(config)
        XCTAssertTrue(merged.text.contains("10.0.0.1 api.test"))
        XCTAssertEqual(merged.records.count, 4)
        XCTAssertNoThrow(try HostsContentValidator().validate(merged.text))
    }

    /// 相同 IPv6 的大小写、压缩和展开形式应去重，输出仍保留首条地址原文。
    func testEquivalentIPv6FormsAreDeduplicatedWithoutRewritingAddress() throws {
        let original = "2001:0DB8:0:0:0:0:0:1"
        var config = AppConfig.initial(defaultHosts: "\(original) api.test\n")
        config.groups = [HostGroup(name: "项目", nodes: [
            HostNode(name: "压缩", content: "2001:db8::1 API.TEST alias.test\n", isActive: true),
            HostNode(name: "展开", content: "2001:0db8:0000:0000:0000:0000:0000:0001 api.test\n", isActive: true)
        ])]

        let merged = try HostsMerger().merge(config)
        XCTAssertEqual(merged.duplicateCount, 2)
        XCTAssertEqual(merged.records.count, 2)
        XCTAssertEqual(merged.records.first?.ipAddress, original)
        XCTAssertEqual(merged.records.last?.hostnames, ["alias.test"])
    }

    /// 地址规范化不能放过真正不同的 IPv6 映射冲突。
    func testDifferentIPv6AddressesStillConflict() {
        let config = AppConfig.initial(defaultHosts: "2001:db8::1 api.test\n2001:db8::2 api.test\n")
        XCTAssertThrowsError(try HostsMerger().merge(config)) { error in
            guard case HostMergeError.conflicts(let conflicts) = error else {
                return XCTFail("应报告 IPv6 冲突，实际：\(error)")
            }
            XCTAssertEqual(conflicts.count, 1)
        }
    }

    /// 原始地址字节相同不代表作用域相同，不能把带接口的地址与无作用域地址合并。
    func testScopedAndUnscopedIPv6RemainDifferentAddresses() {
        let config = AppConfig.initial(defaultHosts: "fe80::1%lo0 api.test\nfe80::1 api.test\n")
        XCTAssertThrowsError(try HostsMerger().merge(config)) { error in
            guard case HostMergeError.conflicts(let conflicts) = error else {
                return XCTFail("应报告作用域不同的 IPv6 冲突，实际：\(error)")
            }
            XCTAssertEqual(conflicts.count, 1)
        }
    }

    /// IPv4 与 IPv4-mapped IPv6 不属于同一地址族，不能相互去重或冲突。
    func testIPv4AndMappedIPv6RemainSeparateAddressFamilies() throws {
        let config = AppConfig.initial(defaultHosts: "127.0.0.1 api.test\n::ffff:127.0.0.1 api.test\n")
        let merged = try HostsMerger().merge(config)
        XCTAssertEqual(merged.records.count, 2)
        XCTAssertEqual(merged.duplicateCount, 0)
    }

    func testDefaultNodeAlwaysParticipatesAndDuplicateEntriesAreCollapsed() throws {
        let config = AppConfig(
            configVersion: 1,
            defaultNode: HostNode(name: "默认", content: "127.0.0.1 localhost\n", isActive: true),
            groups: [
                HostGroup(
                    name: "项目 A",
                    isSingleSelect: true,
                    nodes: [
                        HostNode(name: "开发", content: "127.0.0.1 localhost\n10.0.0.2 api.test\n", isActive: true),
                        HostNode(name: "生产", content: "10.0.0.3 api.test\n", isActive: false)
                    ]
                )
            ],
            settings: AppSettings(launchAtLogin: false),
            state: AppStateMetadata()
        )

        let merged = try HostsMerger().merge(config)

        XCTAssertTrue(merged.text.contains("# 默认"))
        XCTAssertTrue(merged.text.contains("# [项目 A]"))
        XCTAssertTrue(merged.text.contains("# 开发"))
        XCTAssertTrue(merged.text.contains("127.0.0.1 localhost"))
        XCTAssertTrue(merged.text.contains("10.0.0.2 api.test"))
        XCTAssertFalse(merged.text.contains("10.0.0.3 api.test"))
        XCTAssertEqual(merged.duplicateCount, 1)
    }

    func testMultipleGroupsMergeCorrectly() throws {
        let config = AppConfig(
            configVersion: 1,
            defaultNode: HostNode(name: "默认", content: "127.0.0.1 localhost\n", isActive: true),
            groups: [
                HostGroup(
                    name: "项目 A",
                    isSingleSelect: true,
                    nodes: [
                        HostNode(name: "开发", content: "10.0.0.1 api.test\n", isActive: true)
                    ]
                ),
                HostGroup(
                    name: "项目 B",
                    isSingleSelect: false,
                    nodes: [
                        HostNode(name: "测试", content: "10.0.0.2 db.test\n", isActive: true)
                    ]
                )
            ],
            settings: AppSettings(launchAtLogin: false),
            state: AppStateMetadata()
        )

        let merged = try HostsMerger().merge(config)

        XCTAssertTrue(merged.text.contains("# [项目 A]"))
        XCTAssertTrue(merged.text.contains("# [项目 B]"))
        XCTAssertTrue(merged.text.contains("10.0.0.1 api.test"))
        XCTAssertTrue(merged.text.contains("10.0.0.2 db.test"))
        XCTAssertEqual(merged.duplicateCount, 0)
    }

    func testInactiveNodeNotIncluded() throws {
        let config = AppConfig(
            configVersion: 1,
            defaultNode: HostNode(name: "默认", content: "127.0.0.1 localhost\n", isActive: true),
            groups: [
                HostGroup(
                    name: "项目 A",
                    isSingleSelect: true,
                    nodes: [
                        HostNode(name: "开发", content: "10.0.0.1 api.test\n", isActive: false),
                        HostNode(name: "生产", content: "10.0.0.2 api.test\n", isActive: true)
                    ]
                )
            ],
            settings: AppSettings(launchAtLogin: false),
            state: AppStateMetadata()
        )

        let merged = try HostsMerger().merge(config)

        XCTAssertFalse(merged.text.contains("10.0.0.1 api.test"))
        XCTAssertTrue(merged.text.contains("10.0.0.2 api.test"))
    }

    func testEmptyConfigGeneratesHeaderOnly() throws {
        let config = AppConfig(
            configVersion: 1,
            defaultNode: HostNode(name: "默认", content: "", isActive: true),
            groups: [],
            settings: AppSettings(launchAtLogin: false),
            state: AppStateMetadata()
        )

        let merged = try HostsMerger().merge(config)
        XCTAssertTrue(merged.text.contains("# --- HostCat Begin (v1) ---"))
        XCTAssertEqual(merged.records.count, 0)
        XCTAssertEqual(merged.duplicateCount, 0)
    }

    func testConflictingHostnamesAreRejected() {
        let config = AppConfig(
            configVersion: 1,
            defaultNode: HostNode(name: "默认", content: "127.0.0.1 api.test\n", isActive: true),
            groups: [
                HostGroup(
                    name: "项目 A",
                    isSingleSelect: true,
                    nodes: [
                        HostNode(name: "开发", content: "10.0.0.2 api.test\n", isActive: true)
                    ]
                )
            ],
            settings: AppSettings(launchAtLogin: false),
            state: AppStateMetadata()
        )

        XCTAssertThrowsError(try HostsMerger().merge(config)) { error in
            guard case HostMergeError.conflicts(let conflicts) = error else {
                return XCTFail("Expected conflict error, got \(error)")
            }

            XCTAssertEqual(conflicts.count, 1)
            XCTAssertEqual(conflicts[0].hostname, "api.test")
            XCTAssertEqual(conflicts[0].existing.ipAddress, "127.0.0.1")
            XCTAssertEqual(conflicts[0].incoming.ipAddress, "10.0.0.2")
        }
    }

    func testMultipleConflictsReported() {
        let config = AppConfig(
            configVersion: 1,
            defaultNode: HostNode(name: "默认", content: "127.0.0.1 api.test\n127.0.0.1 db.test\n", isActive: true),
            groups: [
                HostGroup(
                    name: "项目 A",
                    isSingleSelect: true,
                    nodes: [
                        HostNode(name: "开发", content: "10.0.0.2 api.test\n10.0.0.3 db.test\n", isActive: true)
                    ]
                )
            ],
            settings: AppSettings(launchAtLogin: false),
            state: AppStateMetadata()
        )

        XCTAssertThrowsError(try HostsMerger().merge(config)) { error in
            guard case HostMergeError.conflicts(let conflicts) = error else {
                return XCTFail("Expected conflict error, got \(error)")
            }
            XCTAssertEqual(conflicts.count, 2)
        }
    }

    func testGroupAndNodeNamesCannotInjectHostsRecords() throws {
        let config = AppConfig(
            configVersion: 1,
            defaultNode: HostNode(name: "默认\n10.0.0.9 injected-default.test", content: "127.0.0.1 localhost\n", isActive: true),
            groups: [
                HostGroup(
                    name: "项目\n10.0.0.8 injected-group.test",
                    isSingleSelect: true,
                    nodes: [
                        HostNode(
                            name: "开发\n10.0.0.7 injected-node.test",
                            content: "10.0.0.2 api.test\n",
                            isActive: true
                        )
                    ]
                )
            ],
            settings: AppSettings(launchAtLogin: false),
            state: AppStateMetadata()
        )

        let merged = try HostsMerger().merge(config)

        XCTAssertFalse(merged.text.components(separatedBy: .newlines).contains("10.0.0.9 injected-default.test"))
        XCTAssertFalse(merged.text.components(separatedBy: .newlines).contains("10.0.0.8 injected-group.test"))
        XCTAssertFalse(merged.text.components(separatedBy: .newlines).contains("10.0.0.7 injected-node.test"))
        XCTAssertTrue(merged.text.contains("10.0.0.2 api.test"))
    }

    func testCommentsAndBlankLinesAreKept() throws {
        let config = AppConfig(
            configVersion: 1,
            defaultNode: HostNode(
                name: "默认",
                content: "# 只在本机使用\n\n127.0.0.1 localhost\n",
                isActive: true
            ),
            groups: [],
            settings: AppSettings(launchAtLogin: false),
            state: AppStateMetadata()
        )

        let merged = try HostsMerger().merge(config)

        XCTAssertTrue(merged.text.contains("# 只在本机使用"))
        XCTAssertTrue(merged.text.contains("127.0.0.1 localhost"))
        XCTAssertEqual(merged.records.count, 1)
    }
}
