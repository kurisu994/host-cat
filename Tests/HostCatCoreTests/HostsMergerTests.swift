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
}
