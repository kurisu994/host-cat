import os.log
import XCTest
@testable import HostCatCore
@testable import HostCatHelperClient

/// Helper 回复解析：只有连接层面的问题才算「Helper 不可用」，写入本身的失败要原样上报。
final class XPCReplyParsingTests: XCTestCase {
    private let logger = Logger(subsystem: "com.hostcat.tests", category: "XPCReplyParsingTests")

    func testWriteFailureIsReportedAsRejectedWrite() {
        let reply: NSDictionary = [
            "success": false,
            "errorCode": "writeFailed",
            "errorMessage": "缺少系统条目 ::1 localhost"
        ]

        XCTAssertThrowsError(try XPCHostHelperClient.parseReply(reply, logger: logger)) { error in
            XCTAssertEqual(error as? HostHelperClientError, .writeRejected("缺少系统条目 ::1 localhost"))
        }
    }

    func testUnknownErrorCodeIsUnexpectedReply() {
        let reply: NSDictionary = [
            "success": false,
            "errorMessage": "未知错误"
        ]

        XCTAssertThrowsError(try XPCHostHelperClient.parseReply(reply, logger: logger)) { error in
            XCTAssertEqual(error as? HostHelperClientError, .unexpectedReply("未知错误"))
        }
    }

    func testHashMismatchKeepsDedicatedError() {
        let reply: NSDictionary = [
            "success": false,
            "errorCode": "hashMismatch",
            "errorMessage": "hosts 已被修改"
        ]

        XCTAssertThrowsError(try XPCHostHelperClient.parseReply(reply, logger: logger)) { error in
            XCTAssertEqual(error as? HostHelperClientError, .hashMismatch)
        }
    }
}
