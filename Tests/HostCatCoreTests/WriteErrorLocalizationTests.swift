import XCTest
@testable import HostCatCore

final class WriteErrorLocalizationTests: XCTestCase {
    func testContentValidationDetailFollowsRequestedLanguage() {
        let error = HostsWriteError.contentValidationFailed(.missingBeginMarker)

        let zh = error.description(in: .simplifiedChinese)
        let en = error.description(in: .english)

        XCTAssertTrue(zh.contains("缺少 HostCat 起始标记"), zh)
        XCTAssertTrue(en.contains("Missing HostCat Begin marker"), en)
        XCTAssertNotEqual(zh, en)
    }

    func testParameterizedDetailKeepsSystemReason() {
        let error = HostsWriteError.permissionSetFailed(.chmodFailed(mode: "644", reason: "Operation not permitted"))

        XCTAssertTrue(error.description(in: .simplifiedChinese).contains("chmod 644 失败：Operation not permitted"))
        XCTAssertTrue(error.description(in: .english).contains("chmod 644 failed: Operation not permitted"))
    }

    func testDNSCommandDetailLocalizes() {
        let error = HostsWriteError.dnsRefreshFailed(.dnsCommandFailed(command: "/usr/bin/killall -HUP mDNSResponder", status: 1, stderr: "x"))

        XCTAssertTrue(error.description(in: .simplifiedChinese).contains("退出码 1"))
        XCTAssertTrue(error.description(in: .english).contains("exited with 1"))
    }

    func testRawDetailPassesThroughUntouched() {
        let error = HostsWriteError.writeFailed("模拟写入失败")

        XCTAssertTrue(error.description(in: .english).contains("模拟写入失败"))
    }

    func testMissingSystemEntryLocalizes() {
        let error = HostsWriteError.contentValidationFailed(.missingSystemEntry(ip: "::1", hostname: "localhost"))

        XCTAssertTrue(error.description(in: .simplifiedChinese).contains("缺少必需的系统条目 ::1 localhost"))
        XCTAssertTrue(error.description(in: .english).contains("Missing required system entry ::1 localhost"))
    }
}
