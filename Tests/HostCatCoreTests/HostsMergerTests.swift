import XCTest
@testable import HostCatCore

final class HostsMergerTests: XCTestCase {
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
}
