import XCTest
@testable import HostCatCore

/// 大文件（5000+ 行）解析 / 校验 / 合并 / 导入 / 哈希 / 写入校验的性能基准。
///
/// 这些测试同时承担两个作用：
/// 1. 用 `measure` 记录耗时基线，便于回归对比；
/// 2. 用宽松的上限断言兜底，防止出现数量级退化（上限远高于当前实测，避免 CI 抖动误报）。
final class LargeHostsPerformanceTests: XCTestCase {
    private static let lineCount = 6000

    /// 只测 3 轮，避免常规 `swift test` 被基准拖慢；需要更稳的基线时可临时调大。
    private static var measureOptions: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        return options
    }

    /// 生成 `count` 行互不冲突的 hosts 记录，穿插注释与空行，贴近真实文件。
    private static func makeHostsText(lines count: Int, prefix: String = "h") -> String {
        var lines: [String] = []
        lines.reserveCapacity(count + count / 10)
        for index in 0..<count {
            if index % 50 == 0 { lines.append("# section \(index / 50)") }
            if index % 200 == 0 { lines.append("") }
            let third = (index / 250) % 250
            let fourth = index % 250 + 1
            lines.append("10.\(index / 62500).\(third).\(fourth) \(prefix)\(index).example.test alias-\(prefix)\(index).test # note \(index)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func makeConfig(nodeCount: Int = 6, linesPerNode: Int = 1000) -> AppConfig {
        var config = AppConfig.initial(defaultHosts: "127.0.0.1 localhost\n255.255.255.255 broadcasthost\n::1 localhost\n")
        let nodes = (0..<nodeCount).map { index in
            HostNode(
                name: "node-\(index)",
                content: Self.makeHostsText(lines: linesPerNode, prefix: "n\(index)-"),
                isActive: true
            )
        }
        config.groups = [HostGroup(name: "perf", nodes: nodes)]
        return config
    }

    /// 断言闭包耗时不超过 `limit` 秒（宽松上限）。
    private func assertFinishes(within limit: TimeInterval, _ label: String, _ block: () throws -> Void) rethrows {
        let start = Date()
        try block()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, limit, "\(label) 耗时 \(elapsed)s 超过上限 \(limit)s")
    }

    func testParse6000LinesPerformance() throws {
        let text = Self.makeHostsText(lines: Self.lineCount)
        let parser = HostsParser()

        measure(options: Self.measureOptions) { _ = try? parser.parse(text) }

        assertFinishes(within: 2, "parse") { XCTAssertEqual(try? parser.parse(text).count, Self.lineCount) }
    }

    func testValidate6000LinesPerformance() {
        let text = Self.makeHostsText(lines: Self.lineCount)
        let parser = HostsParser()

        measure(options: Self.measureOptions) { _ = parser.validate(text) }

        assertFinishes(within: 2, "validate") { XCTAssertTrue(parser.validate(text).isEmpty) }
    }

    func testValidateManyErrorLinesPerformance() {
        // 每行都有错的最坏情况，错误收集不应退化成 O(n²)
        let text = (0..<Self.lineCount).map { "not-an-ip host\($0).test" }.joined(separator: "\n")
        let parser = HostsParser()

        measure(options: Self.measureOptions) { _ = parser.validate(text) }

        assertFinishes(within: 3, "validate-errors") { XCTAssertEqual(parser.validate(text).count, Self.lineCount) }
    }

    func testMerge6000LinesAcrossNodesPerformance() throws {
        let config = makeConfig(nodeCount: 6, linesPerNode: 1000)
        let merger = HostsMerger()

        measure(options: Self.measureOptions) { _ = try? merger.merge(config) }

        assertFinishes(within: 3, "merge") {
            let merged = try? merger.merge(config)
            XCTAssertEqual(merged?.records.count, 6000 + 3)
        }
    }

    func testMergeHeavyDuplicatesPerformance() throws {
        // 多个节点重复同一批条目，覆盖去重路径
        var config = AppConfig.initial(defaultHosts: "127.0.0.1 localhost\n255.255.255.255 broadcasthost\n::1 localhost\n")
        let shared = Self.makeHostsText(lines: 1500, prefix: "dup")
        config.groups = [HostGroup(name: "dups", nodes: (0..<4).map {
            HostNode(name: "n\($0)", content: shared, isActive: true)
        })]
        let merger = HostsMerger()

        measure(options: Self.measureOptions) { _ = try? merger.merge(config) }

        assertFinishes(within: 3, "merge-dups") {
            let merged = try? merger.merge(config)
            // 每行含主机名 + 别名共 2 个 hostname，重复数按 hostname 计：2 × 1500 × 3 个重复节点
            XCTAssertEqual(merged?.duplicateCount, 2 * 1500 * 3)
        }
    }

    func testImportHosts6000LinesPerformance() {
        let text = "127.0.0.1 localhost\n255.255.255.255 broadcasthost\n::1 localhost\n" + Self.makeHostsText(lines: Self.lineCount)
        let importer = HostsImporter()

        measure(options: Self.measureOptions) { _ = importer.importHosts(text) }

        assertFinishes(within: 2, "import") { _ = importer.importHosts(text) }
    }

    func testHash6000LinesPerformance() {
        let text = Self.makeHostsText(lines: Self.lineCount)

        measure(options: Self.measureOptions) { _ = HostsHash.sha256Hex(text) }

        assertFinishes(within: 1, "hash") { _ = HostsHash.sha256Hex(text) }
    }

    func testWriteValidationOfMergedLargeHostsPerformance() throws {
        let merged = try HostsMerger().merge(makeConfig(nodeCount: 6, linesPerNode: 1000))
        let validator = HostsContentValidator()

        measure(options: Self.measureOptions) { try? validator.validate(merged.text) }

        try assertFinishes(within: 3, "write-validate") { try validator.validate(merged.text) }
    }

    func testConfigSaveLoadWithLargeNodesPerformance() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HostCat-perf-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AppConfigStore(configURL: url)
        let config = makeConfig(nodeCount: 6, linesPerNode: 1000)

        measure(options: Self.measureOptions) {
            try? store.save(config)
            _ = try? store.load(defaultHosts: "")
        }

        try assertFinishes(within: 3, "config-roundtrip") {
            try store.save(config)
            XCTAssertEqual(try store.load(defaultHosts: "").config.groups.first?.nodes.count, 6)
        }
    }
}
