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

    func testRejectsMissingHostname() {
        XCTAssertThrowsError(try HostsParser().parse("127.0.0.1\n")) { error in
            guard case HostsParseError.missingHostname(let lineNumber) = error else {
                return XCTFail("Expected missingHostname error, got \(error)")
            }

            XCTAssertEqual(lineNumber, 1)
        }
    }
}
