import XCTest
@testable import HostCatCore

final class ConfigTransferServiceTests: XCTestCase {
    private let service = ConfigTransferService()

    private func makeConfig() -> AppConfig {
        var config = AppConfig.initial(defaultHosts: "127.0.0.1 localhost\n")
        config.groups = [
            HostGroup(name: "开发", nodes: [
                HostNode(name: "本地", content: "127.0.0.1 a.test\n", isActive: true),
                HostNode(name: "测试", content: "10.0.0.1 b.test\n", isActive: false)
            ])
        ]
        config.settings.launchAtLogin = true
        config.state = AppStateMetadata(
            lastAppliedHostsHash: "hash",
            lastAppliedAt: Date(timeIntervalSince1970: 100),
            lastExternalHostsHash: "ext"
        )
        return config
    }

    // MARK: - Export

    func testExportClearsMachineSpecificState() throws {
        let config = makeConfig()
        let data = try service.exportData(config)
        let decoded = try JSONDecoder.hostCatConfigDecoder.decode(AppConfig.self, from: data)

        XCTAssertEqual(decoded.state, AppStateMetadata())
        XCTAssertEqual(decoded.groups, config.groups)
    }

    // MARK: - Decode / Validate

    func testDecodeRejectsInvalidJSON() {
        XCTAssertThrowsError(try service.decode(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? ConfigTransferError, .invalidFormat)
        }
    }

    func testDecodeRejectsNewerVersion() throws {
        var config = makeConfig()
        config.configVersion = AppConfigStore.currentConfigVersion + 1
        let data = try JSONEncoder.hostCatConfigEncoder.encode(config)

        XCTAssertThrowsError(try service.decode(data)) { error in
            XCTAssertEqual(
                error as? ConfigTransferError,
                .unsupportedVersion(AppConfigStore.currentConfigVersion + 1)
            )
        }
    }

    func testDecodeRejectsVersionBelowOne() throws {
        var config = makeConfig()
        config.configVersion = 0
        let data = try JSONEncoder.hostCatConfigEncoder.encode(config)

        XCTAssertThrowsError(try service.decode(data)) { error in
            XCTAssertEqual(error as? ConfigTransferError, .unsupportedVersion(0))
        }
    }

    func testDecodeNormalizesCurrentRules() throws {
        var config = makeConfig()
        config.defaultNode.isActive = false
        config.groups[0].isSingleSelect = true
        let data = try JSONEncoder.hostCatConfigEncoder.encode(config)

        let decoded = try service.decode(data)

        XCTAssertTrue(decoded.defaultNode.isActive)
        XCTAssertFalse(decoded.groups[0].isSingleSelect)
    }

    func testExportThenDecodeRoundTrips() throws {
        let original = makeConfig()
        let decoded = try service.decode(service.exportData(original))

        XCTAssertEqual(decoded.defaultNode, original.defaultNode)
        XCTAssertEqual(decoded.groups, original.groups)
    }

    // MARK: - Replace

    func testReplaceKeepsLocalSettingsAndState() {
        var current = makeConfig()
        current.groups = []
        var imported = AppConfig.initial(defaultHosts: "10.9.9.9 imported.test\n")
        imported.settings.launchAtLogin = false
        imported.groups = [HostGroup(name: "新组", nodes: [HostNode(name: "n", content: "1.1.1.1 n.test\n", isActive: true)])]

        let result = service.apply(imported, to: current, mode: .replace)

        XCTAssertEqual(result.config.groups, imported.groups)
        XCTAssertEqual(result.config.defaultNode.content, "10.9.9.9 imported.test\n")
        XCTAssertEqual(result.config.defaultNode.id, current.defaultNode.id)
        XCTAssertTrue(result.config.settings.launchAtLogin)
        XCTAssertEqual(result.config.state, current.state)
        XCTAssertEqual(result.summary.addedGroups, 1)
        XCTAssertEqual(result.summary.addedNodes, 1)
    }

    // MARK: - Merge

    func testMergeOverwritesSameNameNodeContentButKeepsLocalActiveState() {
        let current = makeConfig()
        var imported = makeConfig()
        imported.groups[0].nodes[0].content = "9.9.9.9 a.test\n"
        imported.groups[0].nodes[0].isActive = false

        let result = service.apply(imported, to: current, mode: .merge)

        let node = result.config.groups[0].nodes[0]
        XCTAssertEqual(node.id, current.groups[0].nodes[0].id)
        XCTAssertEqual(node.content, "9.9.9.9 a.test\n")
        XCTAssertTrue(node.isActive)
        XCTAssertEqual(result.summary.updatedNodes, 1)
        XCTAssertEqual(result.summary.addedNodes, 0)
    }

    func testMergeAppendsNewNodesAndGroupsWithFreshIDs() {
        let current = makeConfig()
        var imported = makeConfig()
        imported.groups[0].nodes.append(HostNode(name: "预发", content: "2.2.2.2 c.test\n", isActive: false))
        imported.groups.append(HostGroup(name: "生产", nodes: [HostNode(name: "p", content: "3.3.3.3 p.test\n", isActive: false)]))

        let result = service.apply(imported, to: current, mode: .merge)

        XCTAssertEqual(result.config.groups.count, 2)
        XCTAssertEqual(result.config.groups[0].nodes.map(\.name), ["本地", "测试", "预发"])
        XCTAssertEqual(result.config.groups[1].name, "生产")
        XCTAssertNotEqual(result.config.groups[1].id, imported.groups[1].id)
        XCTAssertNotEqual(result.config.groups[0].nodes[2].id, imported.groups[0].nodes[2].id)
        XCTAssertEqual(result.summary.addedGroups, 1)
        XCTAssertEqual(result.summary.addedNodes, 2)
    }

    func testMergeNewNodesAreInactive() {
        let current = makeConfig()
        var imported = makeConfig()
        imported.groups.append(HostGroup(name: "生产", nodes: [HostNode(name: "p", content: "3.3.3.3 p.test\n", isActive: true)]))

        let result = service.apply(imported, to: current, mode: .merge)

        XCTAssertFalse(result.config.groups[1].nodes[0].isActive)
    }

    func testMergeDoesNotTouchDefaultNode() {
        var current = makeConfig()
        current.defaultNode.content = "127.0.0.1 mine\n"
        var imported = makeConfig()
        imported.defaultNode.content = "8.8.8.8 other\n"

        let result = service.apply(imported, to: current, mode: .merge)

        XCTAssertEqual(result.config.defaultNode.content, "127.0.0.1 mine\n")
    }
}
