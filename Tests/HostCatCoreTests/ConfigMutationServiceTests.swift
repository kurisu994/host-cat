import XCTest
@testable import HostCatCore

final class ConfigMutationServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeConfig(
        defaultContent: String = "127.0.0.1 localhost",
        groups: [HostGroup] = []
    ) -> AppConfig {
        AppConfig(
            configVersion: 1,
            defaultNode: HostNode(name: "默认", content: defaultContent, isActive: true),
            groups: groups,
            settings: AppSettings(launchAtLogin: false),
            state: AppStateMetadata()
        )
    }

    private func makeGroup(
        name: String,
        isSingleSelect: Bool = false,
        nodes: [HostNode] = []
    ) -> HostGroup {
        HostGroup(name: name, isSingleSelect: isSingleSelect, nodes: nodes)
    }

    private func makeNode(name: String, content: String = "", isActive: Bool = false) -> HostNode {
        HostNode(name: name, content: content, isActive: isActive)
    }

    // MARK: - Group Operations

    func testAddGroupAppendsToEnd() {
        var config = makeConfig()
        let service = ConfigMutationService()

        service.addGroup(named: "开发环境", to: &config)

        XCTAssertEqual(config.groups.count, 1)
        XCTAssertEqual(config.groups[0].name, "开发环境")
        XCTAssertFalse(config.groups[0].isSingleSelect)
        XCTAssertTrue(config.groups[0].nodes.isEmpty)
    }

    func testRemoveGroupByID() {
        var config = makeConfig(groups: [
            makeGroup(name: "A"),
            makeGroup(name: "B")
        ])
        let service = ConfigMutationService()
        let idToRemove = config.groups[0].id

        service.removeGroup(id: idToRemove, from: &config)

        XCTAssertEqual(config.groups.count, 1)
        XCTAssertEqual(config.groups[0].name, "B")
    }

    func testRenameGroup() {
        var config = makeConfig(groups: [makeGroup(name: "旧名字")])
        let service = ConfigMutationService()
        let id = config.groups[0].id

        service.renameGroup(id: id, to: "新名字", in: &config)

        XCTAssertEqual(config.groups[0].name, "新名字")
    }

    func testMoveGroupUp() {
        var config = makeConfig(groups: [
            makeGroup(name: "A"),
            makeGroup(name: "B"),
            makeGroup(name: "C")
        ])
        let service = ConfigMutationService()
        let id = config.groups[1].id

        service.moveGroup(id: id, direction: .up, in: &config)

        XCTAssertEqual(config.groups.map(\.name), ["B", "A", "C"])
    }

    func testMoveGroupDown() {
        var config = makeConfig(groups: [
            makeGroup(name: "A"),
            makeGroup(name: "B"),
            makeGroup(name: "C")
        ])
        let service = ConfigMutationService()
        let id = config.groups[1].id

        service.moveGroup(id: id, direction: .down, in: &config)

        XCTAssertEqual(config.groups.map(\.name), ["A", "C", "B"])
    }

    func testMoveGroupUpAtTopBoundaryIsNoOp() {
        var config = makeConfig(groups: [
            makeGroup(name: "A"),
            makeGroup(name: "B")
        ])
        let service = ConfigMutationService()
        let id = config.groups[0].id

        service.moveGroup(id: id, direction: .up, in: &config)

        XCTAssertEqual(config.groups.map(\.name), ["A", "B"])
    }

    func testMoveGroupDownAtBottomBoundaryIsNoOp() {
        var config = makeConfig(groups: [
            makeGroup(name: "A"),
            makeGroup(name: "B")
        ])
        let service = ConfigMutationService()
        let id = config.groups[1].id

        service.moveGroup(id: id, direction: .down, in: &config)

        XCTAssertEqual(config.groups.map(\.name), ["A", "B"])
    }

    // MARK: - Node Operations

    func testAddNodeToGroup() {
        var config = makeConfig(groups: [makeGroup(name: "开发")])
        let service = ConfigMutationService()
        let groupID = config.groups[0].id

        service.addNode(named: "测试", content: "10.0.0.1 api.test", toGroup: groupID, in: &config)

        XCTAssertEqual(config.groups[0].nodes.count, 1)
        XCTAssertEqual(config.groups[0].nodes[0].name, "测试")
        XCTAssertEqual(config.groups[0].nodes[0].content, "10.0.0.1 api.test")
        XCTAssertFalse(config.groups[0].nodes[0].isActive)
    }

    func testRemoveNodeFromGroup() {
        let node1 = makeNode(name: "N1")
        let node2 = makeNode(name: "N2")
        var config = makeConfig(groups: [makeGroup(name: "G", nodes: [node1, node2])])
        let service = ConfigMutationService()
        let groupID = config.groups[0].id

        service.removeNode(id: node1.id, fromGroup: groupID, in: &config)

        XCTAssertEqual(config.groups[0].nodes.count, 1)
        XCTAssertEqual(config.groups[0].nodes[0].name, "N2")
    }

    func testRenameNode() {
        let node = makeNode(name: "旧节点")
        var config = makeConfig(groups: [makeGroup(name: "G", nodes: [node])])
        let service = ConfigMutationService()
        let groupID = config.groups[0].id

        service.renameNode(id: node.id, to: "新节点", inGroup: groupID, in: &config)

        XCTAssertEqual(config.groups[0].nodes[0].name, "新节点")
    }

    func testMoveNodeUp() {
        let n1 = makeNode(name: "N1")
        let n2 = makeNode(name: "N2")
        let n3 = makeNode(name: "N3")
        var config = makeConfig(groups: [makeGroup(name: "G", nodes: [n1, n2, n3])])
        let service = ConfigMutationService()
        let groupID = config.groups[0].id

        service.moveNode(id: n2.id, direction: .up, inGroup: groupID, in: &config)

        XCTAssertEqual(config.groups[0].nodes.map(\.name), ["N2", "N1", "N3"])
    }

    func testMoveNodeDown() {
        let n1 = makeNode(name: "N1")
        let n2 = makeNode(name: "N2")
        let n3 = makeNode(name: "N3")
        var config = makeConfig(groups: [makeGroup(name: "G", nodes: [n1, n2, n3])])
        let service = ConfigMutationService()
        let groupID = config.groups[0].id

        service.moveNode(id: n2.id, direction: .down, inGroup: groupID, in: &config)

        XCTAssertEqual(config.groups[0].nodes.map(\.name), ["N1", "N3", "N2"])
    }

    // MARK: - Default Node Protection

    func testDefaultNodeCannotBeDeleted() {
        var config = makeConfig()
        let service = ConfigMutationService()

        service.removeDefaultNode(from: &config)

        XCTAssertEqual(config.defaultNode.name, "默认")
    }

    func testDefaultNodeCannotBeDeactivated() {
        var config = makeConfig()
        let service = ConfigMutationService()

        service.setDefaultNodeActive(false, in: &config)

        XCTAssertTrue(config.defaultNode.isActive)
    }

    func testDefaultNodeCanBeRenamed() {
        var config = makeConfig()
        let service = ConfigMutationService()

        service.renameDefaultNode(to: "系统默认", in: &config)

        XCTAssertEqual(config.defaultNode.name, "系统默认")
    }

    // MARK: - Node Activation (Multi-Select)

    func testMultiSelectActivatesIndependently() {
        let n1 = makeNode(name: "N1", isActive: true)
        let n2 = makeNode(name: "N2", isActive: false)
        var config = makeConfig(groups: [makeGroup(name: "G", nodes: [n1, n2])])
        let service = ConfigMutationService()
        let groupID = config.groups[0].id

        service.setNodeActive(id: n2.id, active: true, inGroup: groupID, in: &config)

        // 多选模式：激活 N2 不影响 N1
        XCTAssertTrue(config.groups[0].nodes[0].isActive)
        XCTAssertTrue(config.groups[0].nodes[1].isActive)
    }

    func testMultiSelectAllowsMultipleActive() {
        let n1 = makeNode(name: "N1", isActive: true)
        let n2 = makeNode(name: "N2", isActive: false)
        var config = makeConfig(groups: [makeGroup(name: "G", nodes: [n1, n2])])
        let service = ConfigMutationService()
        let groupID = config.groups[0].id

        service.setNodeActive(id: n2.id, active: true, inGroup: groupID, in: &config)

        XCTAssertTrue(config.groups[0].nodes[0].isActive)
        XCTAssertTrue(config.groups[0].nodes[1].isActive)
    }

    func testDeactivateNode() {
        let n1 = makeNode(name: "N1", isActive: true)
        var config = makeConfig(groups: [makeGroup(name: "G", nodes: [n1])])
        let service = ConfigMutationService()
        let groupID = config.groups[0].id

        service.setNodeActive(id: n1.id, active: false, inGroup: groupID, in: &config)

        XCTAssertFalse(config.groups[0].nodes[0].isActive)
    }

    func testActivationDoesNotAffectOtherGroups() {
        let n1a = makeNode(name: "N1A", isActive: true)
        let n1b = makeNode(name: "N1B", isActive: false)
        let n2a = makeNode(name: "N2A", isActive: false)
        var config = makeConfig(groups: [
            makeGroup(name: "G1", nodes: [n1a, n1b]),
            makeGroup(name: "G2", nodes: [n2a])
        ])
        let service = ConfigMutationService()
        let group1ID = config.groups[0].id

        service.setNodeActive(id: n1b.id, active: true, inGroup: group1ID, in: &config)

        // 多选模式：两个都激活，不影响其他分组
        XCTAssertTrue(config.groups[0].nodes[0].isActive)
        XCTAssertTrue(config.groups[0].nodes[1].isActive)
        XCTAssertFalse(config.groups[1].nodes[0].isActive)
    }

    func testSetGroupSingleSelect() {
        var config = makeConfig(groups: [makeGroup(name: "G", isSingleSelect: true)])
        let service = ConfigMutationService()
        let groupID = config.groups[0].id

        service.setGroupSingleSelect(false, forGroup: groupID, in: &config)

        XCTAssertFalse(config.groups[0].isSingleSelect)
    }

    // MARK: - Node Content Update

    func testUpdateNodeContent() {
        let node = makeNode(name: "N", content: "old")
        var config = makeConfig(groups: [makeGroup(name: "G", nodes: [node])])
        let service = ConfigMutationService()
        let groupID = config.groups[0].id

        service.updateNodeContent(id: node.id, content: "new content", inGroup: groupID, in: &config)

        XCTAssertEqual(config.groups[0].nodes[0].content, "new content")
    }

    func testUpdateDefaultNodeContent() {
        var config = makeConfig(defaultContent: "old")
        let service = ConfigMutationService()

        service.updateDefaultNodeContent("new default", in: &config)

        XCTAssertEqual(config.defaultNode.content, "new default")
    }
}
