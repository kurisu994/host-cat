import XCTest
@testable import HostCatCore

final class AppConfigTests: XCTestCase {
    func testInitialConfigStoresDefaultNodeAndStateMetadata() {
        let config = AppConfig.initial(defaultHosts: "127.0.0.1 localhost\n")

        XCTAssertEqual(config.configVersion, 1)
        XCTAssertEqual(config.defaultNode.name, "默认")
        XCTAssertTrue(config.defaultNode.isActive)
        XCTAssertEqual(config.defaultNode.content, "127.0.0.1 localhost\n")
        XCTAssertEqual(config.groups, [])
        XCTAssertNil(config.state.lastAppliedHostsHash)
        XCTAssertNil(config.state.lastAppliedAt)
        XCTAssertNil(config.state.lastExternalHostsHash)
    }

    func testHostsHashIsStableForSameContent() {
        let first = HostsHash.sha256Hex("127.0.0.1 localhost\n")
        let second = HostsHash.sha256Hex("127.0.0.1 localhost\n")

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 64)
    }
}
