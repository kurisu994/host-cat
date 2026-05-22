import XCTest
@testable import HostCatCore

final class ModelsTests: XCTestCase {

    // MARK: - HostNode Codable

    func testHostNodeCodableRoundTrip() throws {
        let node = HostNode(name: "测试节点", content: "127.0.0.1 test\n", isActive: true)
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(HostNode.self, from: data)

        XCTAssertEqual(decoded, node)
        XCTAssertEqual(decoded.name, "测试节点")
        XCTAssertEqual(decoded.content, "127.0.0.1 test\n")
        XCTAssertTrue(decoded.isActive)
    }

    func testHostNodeIdPreservedAcrossCoding() throws {
        let node = HostNode(name: "ID 保持", content: "", isActive: false)
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(HostNode.self, from: data)

        XCTAssertEqual(decoded.id, node.id)
    }

    // MARK: - HostGroup Codable

    func testHostGroupCodableRoundTrip() throws {
        let nodes = [
            HostNode(name: "节点A", content: "1.2.3.4 a\n", isActive: true),
            HostNode(name: "节点B", content: "5.6.7.8 b\n", isActive: false),
        ]
        let group = HostGroup(name: "开发环境", isSingleSelect: true, nodes: nodes)
        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(HostGroup.self, from: data)

        XCTAssertEqual(decoded, group)
        XCTAssertEqual(decoded.name, "开发环境")
        XCTAssertTrue(decoded.isSingleSelect)
        XCTAssertEqual(decoded.nodes.count, 2)
        XCTAssertEqual(decoded.nodes[0].name, "节点A")
        XCTAssertEqual(decoded.nodes[1].name, "节点B")
    }

    func testEmptyGroupCodableRoundTrip() throws {
        let group = HostGroup(name: "空分组")
        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(HostGroup.self, from: data)

        XCTAssertEqual(decoded, group)
        XCTAssertEqual(decoded.nodes, [])
        XCTAssertFalse(decoded.isSingleSelect)
    }

    // MARK: - AppSettings Codable

    func testAppSettingsCodableRoundTrip() throws {
        let settings = AppSettings(launchAtLogin: true)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
        XCTAssertTrue(decoded.launchAtLogin)
    }

    // MARK: - AppStateMetadata Codable

    func testAppStateMetadataCodableRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let state = AppStateMetadata(
            lastAppliedHostsHash: "abc123",
            lastAppliedAt: date,
            lastExternalHostsHash: "def456"
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        let decoded = try JSONDecoder().decode(AppStateMetadata.self, from: data)

        XCTAssertEqual(decoded, state)
        XCTAssertEqual(decoded.lastAppliedHostsHash, "abc123")
        XCTAssertEqual(decoded.lastExternalHostsHash, "def456")
    }

    func testAppStateMetadataNilFieldsCodableRoundTrip() throws {
        let state = AppStateMetadata()
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(AppStateMetadata.self, from: data)

        XCTAssertEqual(decoded, state)
        XCTAssertNil(decoded.lastAppliedHostsHash)
        XCTAssertNil(decoded.lastAppliedAt)
        XCTAssertNil(decoded.lastExternalHostsHash)
    }

    // MARK: - AppConfig Codable

    func testAppConfigCodableRoundTrip() throws {
        let config = AppConfig.initial(defaultHosts: "127.0.0.1 localhost\n", currentHostsHash: "hash123")
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

        XCTAssertEqual(decoded, config)
        XCTAssertEqual(decoded.configVersion, 1)
        XCTAssertEqual(decoded.defaultNode.name, "默认")
        XCTAssertEqual(decoded.defaultNode.content, "127.0.0.1 localhost\n")
    }

    func testAppConfigWithGroupsCodableRoundTrip() throws {
        var config = AppConfig.initial(defaultHosts: "127.0.0.1 localhost\n")
        config.groups = [
            HostGroup(name: "组1", nodes: [
                HostNode(name: "节点1", content: "10.0.0.1 dev\n", isActive: true),
            ]),
            HostGroup(name: "组2", isSingleSelect: true, nodes: [
                HostNode(name: "节点2", content: "10.0.0.2 staging\n", isActive: false),
                HostNode(name: "节点3", content: "10.0.0.3 prod\n", isActive: true),
            ]),
        ]

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

        XCTAssertEqual(decoded, config)
        XCTAssertEqual(decoded.groups.count, 2)
        XCTAssertEqual(decoded.groups[0].nodes.count, 1)
        XCTAssertEqual(decoded.groups[1].nodes.count, 2)
        XCTAssertTrue(decoded.groups[1].isSingleSelect)
    }

    // MARK: - Equatable

    func testHostNodeEqualityByValue() {
        let id = UUID()
        let node1 = HostNode(id: id, name: "A", content: "x", isActive: true)
        let node2 = HostNode(id: id, name: "A", content: "x", isActive: true)
        let node3 = HostNode(id: id, name: "A", content: "y", isActive: true)

        XCTAssertEqual(node1, node2)
        XCTAssertNotEqual(node1, node3)
    }

    func testAppSettingsEquality() {
        let s1 = AppSettings(launchAtLogin: true)
        let s2 = AppSettings(launchAtLogin: true)
        let s3 = AppSettings(launchAtLogin: false)

        XCTAssertEqual(s1, s2)
        XCTAssertNotEqual(s1, s3)
    }

    func testAppStateMetadataEquality() {
        let m1 = AppStateMetadata(lastAppliedHostsHash: "a")
        let m2 = AppStateMetadata(lastAppliedHostsHash: "a")
        let m3 = AppStateMetadata(lastAppliedHostsHash: "b")

        XCTAssertEqual(m1, m2)
        XCTAssertNotEqual(m1, m3)
    }
}
