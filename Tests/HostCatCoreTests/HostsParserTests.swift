import XCTest
@testable import HostCatCore

final class HostsParserTests: XCTestCase {
    func testParsesIPv4LineWithAliasesAndTrailingComment() throws {
        let records = try HostsParser().parse("127.0.0.1 localhost local.test # development\n")

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].ipAddress, "127.0.0.1")
        XCTAssertEqual(records[0].hostnames, ["localhost", "local.test"])
        XCTAssertEqual(records[0].comment, "development")
        XCTAssertEqual(records[0].lineNumber, 1)
    }

    func testParsesIPv6Line() throws {
        let records = try HostsParser().parse("::1 localhost\n")

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].ipAddress, "::1")
        XCTAssertEqual(records[0].hostnames, ["localhost"])
    }

    func testRejectsInvalidIPAddress() {
        XCTAssertThrowsError(try HostsParser().parse("999.0.0.1 bad.test\n")) { error in
            guard case HostsParseError.invalidIPAddress(let lineNumber, let value) = error else {
                return XCTFail("Expected invalidIPAddress error, got \(error)")
            }

            XCTAssertEqual(lineNumber, 1)
            XCTAssertEqual(value, "999.0.0.1")
        }
    }

    func testParsesMultipleLines() throws {
        let content = """
            127.0.0.1 localhost
            10.0.0.1 api.test
            192.168.1.1 router.local
            """
        let records = try HostsParser().parse(content)
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records[0].ipAddress, "127.0.0.1")
        XCTAssertEqual(records[2].hostnames, ["router.local"])
    }

    func testParsesLineWithMultipleAliases() throws {
        let records = try HostsParser().parse("10.0.0.1 host1 host2 host3\n")
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].hostnames, ["host1", "host2", "host3"])
    }

    func testIgnoresBlankLinesAndComments() throws {
        let content = """
            # This is a comment

            127.0.0.1 localhost

            # Another comment
            10.0.0.1 api.test
            """
        let records = try HostsParser().parse(content)
        XCTAssertEqual(records.count, 2)
    }

    func testRejectsInvalidIPv6Address() {
        XCTAssertThrowsError(try HostsParser().parse("::ggg localhost\n")) { error in
            guard case HostsParseError.invalidIPAddress(let lineNumber, let value) = error else {
                return XCTFail("Expected invalidIPAddress error, got \(error)")
            }
            XCTAssertEqual(lineNumber, 1)
            XCTAssertEqual(value, "::ggg")
        }
    }

    func testRejectsEmptyContent() {
        XCTAssertThrowsError(try HostsParser().parse("")) { error in
            guard case HostsParseError.emptyContent = error else {
                return XCTFail("Expected emptyContent error, got \(error)")
            }
        }
    }

    func testTracksLineNumbers() throws {
        let content = """
            # comment

            127.0.0.1 localhost
            10.0.0.1 api.test
            """
        let records = try HostsParser().parse(content)
        XCTAssertEqual(records[0].lineNumber, 3)
        XCTAssertEqual(records[1].lineNumber, 4)
    }
}
