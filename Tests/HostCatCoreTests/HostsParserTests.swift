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

    func testParsesOnlyCommentsReturnsEmptyRecords() throws {
        let records = try HostsParser().parse("# This is a comment\n# Another comment\n")
        XCTAssertEqual(records.count, 0)
    }

    func testParsesEmptyContentReturnsEmptyRecords() throws {
        let records = try HostsParser().parse("")
        XCTAssertEqual(records.count, 0)
    }

    func testParsesTabSeparatedLine() throws {
        let records = try HostsParser().parse("127.0.0.1\tlocalhost\tlocal.test\n")

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].ipAddress, "127.0.0.1")
        XCTAssertEqual(records[0].hostnames, ["localhost", "local.test"])
    }

    func testParsesHostnameWithUnderscore() throws {
        let records = try HostsParser().parse("127.0.0.1 my_host.local\n")

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].hostnames, ["my_host.local"])
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

    func testValidateCollectsMultipleErrors() {
        let content = """
            999.0.0.1 bad.test
            127.0.0.1
            10.0.0.1 valid.test
            ::ggg bad_ipv6.test
            """
        let errors = HostsParser().validate(content)
        XCTAssertEqual(errors.count, 3)

        guard case .invalidIPAddress(let line1, let val1) = errors[0] else {
            return XCTFail("Expected invalidIPAddress error on line 1, got \(errors[0])")
        }
        XCTAssertEqual(line1, 1)
        XCTAssertEqual(val1, "999.0.0.1")

        guard case .missingHostname(let line2) = errors[1] else {
            return XCTFail("Expected missingHostname error on line 2, got \(errors[1])")
        }
        XCTAssertEqual(line2, 2)

        guard case .invalidIPAddress(let line4, let val4) = errors[2] else {
            return XCTFail("Expected invalidIPAddress error on line 4, got \(errors[2])")
        }
        XCTAssertEqual(line4, 4)
        XCTAssertEqual(val4, "::ggg")
    }

    func testValidateCollectsInvalidHostnamesWithoutStoppingAtFirstOne() {
        let content = """
            # comment
            127.0.0.1 valid.test -bad.test bad..test

            10.0.0.1 ok.test
            """

        let errors = HostsParser().validate(content)

        XCTAssertEqual(errors.count, 2)
        guard case .invalidHostname(let line2a, let value2a) = errors[0] else {
            return XCTFail("Expected invalidHostname error on line 2, got \(errors[0])")
        }
        XCTAssertEqual(line2a, 2)
        XCTAssertEqual(value2a, "-bad.test")

        guard case .invalidHostname(let line2b, let value2b) = errors[1] else {
            return XCTFail("Expected invalidHostname error on line 2, got \(errors[1])")
        }
        XCTAssertEqual(line2b, 2)
        XCTAssertEqual(value2b, "bad..test")
    }
}
