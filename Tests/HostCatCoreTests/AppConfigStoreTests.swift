import Darwin
import Foundation
import XCTest
@testable import HostCatCore

final class AppConfigStoreTests: XCTestCase {
    func testDefaultConfigURLUsesApplicationSupportDirectory() {
        let url = AppConfigStore.defaultConfigURL()

        XCTAssertEqual(url.lastPathComponent, "config.json")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "com.hostcat.app")
        XCTAssertTrue(url.path.contains("Application Support"))
    }

    func testLoadCreatesAndPersistsDefaultConfigWhenFileIsMissing() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let configURL = directory.appendingPathComponent("config.json")
        let store = AppConfigStore(configURL: configURL)

        let result = try store.load(defaultHosts: "127.0.0.1 localhost\n")

        XCTAssertEqual(result.status, .createdDefault)
        assertDefaultConfig(result.config, defaultHosts: "127.0.0.1 localhost\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
        XCTAssertEqual(try decodeConfig(at: configURL), result.config)
    }

    func testLoadCreatesDefaultConfigWithExternalHostsHashWhenFileIsMissing() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let configURL = directory.appendingPathComponent("config.json")
        let store = AppConfigStore(configURL: configURL)

        let result = try store.load(defaultHosts: "127.0.0.1 localhost\n", currentHostsHash: "current_hash")

        XCTAssertEqual(result.status, .createdDefault)
        XCTAssertEqual(result.config.state.lastExternalHostsHash, "current_hash")
    }

    func testSaveAndLoadRoundTripExistingConfig() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let configURL = directory.appendingPathComponent("nested/config.json")
        let store = AppConfigStore(configURL: configURL)
        let config = AppConfig(
            configVersion: 1,
            defaultNode: HostNode(name: "默认", content: "127.0.0.1 localhost\n", isActive: true),
            groups: [
                HostGroup(
                    name: "项目 A",
                    isSingleSelect: false,
                    nodes: [
                        HostNode(name: "开发", content: "10.0.0.2 api.test\n", isActive: true)
                    ]
                )
            ],
            settings: AppSettings(launchAtLogin: true),
            state: AppStateMetadata(
                lastAppliedHostsHash: "abc123",
                lastAppliedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )

        try store.save(config)
        let result = try store.load(defaultHosts: "fallback\n")

        XCTAssertEqual(result.status, .loadedExisting)
        XCTAssertEqual(result.config, config)
    }

    func testLoadBackfillsExternalHostsHashForExistingConfigWithoutHashes() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let configURL = directory.appendingPathComponent("config.json")
        let original = AppConfig.initial(defaultHosts: "127.0.0.1 localhost\n")
        try JSONEncoder.hostCatConfigEncoder.encode(original).write(to: configURL)

        let result = try AppConfigStore(configURL: configURL).load(
            defaultHosts: "fallback\n",
            currentHostsHash: "current_hash"
        )

        XCTAssertEqual(result.status, .loadedExisting)
        XCTAssertEqual(result.config.state.lastExternalHostsHash, "current_hash")
    }

    func testLoadDoesNotBackfillExternalHashWhenAppliedHashExists() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let configURL = directory.appendingPathComponent("config.json")
        var original = AppConfig.initial(defaultHosts: "127.0.0.1 localhost\n")
        original.state.lastAppliedHostsHash = "applied_hash"
        try JSONEncoder.hostCatConfigEncoder.encode(original).write(to: configURL)

        let result = try AppConfigStore(configURL: configURL).load(
            defaultHosts: "fallback\n",
            currentHostsHash: "current_hash"
        )

        XCTAssertEqual(result.config.state.lastAppliedHostsHash, "applied_hash")
        XCTAssertNil(result.config.state.lastExternalHostsHash)
    }

    func testLoadNormalizesLegacySingleSelectGroupsToMultiSelect() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let configURL = directory.appendingPathComponent("config.json")
        var config = AppConfig.initial(defaultHosts: "127.0.0.1 localhost\n")
        config.groups = [
            HostGroup(name: "旧分组", isSingleSelect: true, nodes: [
                HostNode(name: "A", content: "10.0.0.1 a.test\n", isActive: true)
            ])
        ]
        try JSONEncoder.hostCatConfigEncoder.encode(config).write(to: configURL)

        let result = try AppConfigStore(configURL: configURL).load(defaultHosts: "fallback\n")

        XCTAssertFalse(result.config.groups[0].isSingleSelect)
    }

    func testCorruptJSONRecoversDefaultConfigAndReportsDisplayableReason() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let configURL = directory.appendingPathComponent("config.json")
        let corruptData = Data("{ invalid json".utf8)
        try corruptData.write(to: configURL)
        let store = AppConfigStore(configURL: configURL)

        let result = try store.load(defaultHosts: "::1 localhost\n")

        XCTAssertEqual(result.status, .recoveredDefault(.invalidJSON))
        assertDefaultConfig(result.config, defaultHosts: "::1 localhost\n")
        XCTAssertEqual(try decodeConfig(at: configURL), result.config)
        let preserved = try preservedConfigs(in: directory, containing: ".corrupt.")
        XCTAssertEqual(preserved.count, 1)
        XCTAssertEqual(try Data(contentsOf: preserved[0]), corruptData)
        XCTAssertNotNil(AppConfigRecoveryReason.invalidJSON.errorDescription)
    }

    func testUnsupportedConfigVersionRecoversDefaultConfigAndReportsVersion() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let configURL = directory.appendingPathComponent("config.json")
        var unsupported = AppConfig.initial(defaultHosts: "127.0.0.1 localhost\n")
        unsupported.configVersion = 99
        try JSONEncoder.hostCatConfigEncoder.encode(unsupported).write(to: configURL)
        let store = AppConfigStore(configURL: configURL)

        let result = try store.load(defaultHosts: "255.255.255.255 broadcasthost\n")

        XCTAssertEqual(result.status, .recoveredDefault(.unsupportedVersion(99)))
        assertDefaultConfig(result.config, defaultHosts: "255.255.255.255 broadcasthost\n")
        XCTAssertEqual(try decodeConfig(at: configURL), result.config)
        let preserved = try preservedConfigs(in: directory, containing: ".unsupported.")
        XCTAssertEqual(preserved.count, 1)
        XCTAssertEqual(try decodeConfig(at: preserved[0]), unsupported)
        XCTAssertNotNil(AppConfigRecoveryReason.unsupportedVersion(99).errorDescription)
    }

    func testSaveFailureDoesNotDestroyExistingConfig() throws {
        let directory = try makeTemporaryDirectory()
        defer {
            _ = chmod(directory.path, 0o700)
            try? FileManager.default.removeItem(at: directory)
        }

        let configURL = directory.appendingPathComponent("config.json")
        let store = AppConfigStore(configURL: configURL)
        let original = AppConfig.initial(defaultHosts: "127.0.0.1 localhost\n")
        let replacement = AppConfig.initial(defaultHosts: "10.0.0.2 api.test\n")
        try store.save(original)

        XCTAssertEqual(chmod(directory.path, 0o500), 0)
        XCTAssertThrowsError(try store.save(replacement))

        XCTAssertEqual(chmod(directory.path, 0o700), 0)
        XCTAssertEqual(try decodeConfig(at: configURL), original)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("HostCatCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func decodeConfig(at url: URL) throws -> AppConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder.hostCatConfigDecoder.decode(AppConfig.self, from: data)
    }

    private func preservedConfigs(in directory: URL, containing token: String) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix("config.json")
                && $0.lastPathComponent.contains(token)
        }
    }

    private func assertDefaultConfig(
        _ config: AppConfig,
        defaultHosts: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(config.configVersion, 1, file: file, line: line)
        XCTAssertEqual(config.defaultNode.name, "默认", file: file, line: line)
        XCTAssertEqual(config.defaultNode.content, defaultHosts, file: file, line: line)
        XCTAssertTrue(config.defaultNode.isActive, file: file, line: line)
        XCTAssertEqual(config.groups, [], file: file, line: line)
        XCTAssertFalse(config.settings.launchAtLogin, file: file, line: line)
        XCTAssertNil(config.state.lastAppliedHostsHash, file: file, line: line)
        XCTAssertNil(config.state.lastAppliedAt, file: file, line: line)
    }
}
