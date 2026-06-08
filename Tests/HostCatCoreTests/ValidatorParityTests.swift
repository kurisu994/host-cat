import XCTest
@testable import HostCatCore

/// 校验 `HostsParser.validate(_:)`（编辑器侧使用）与
/// `HostsContentValidator.validate(_:)`（写入侧使用）的一致性。
///
/// 一致性规则：
/// - 任何被 `HostsParser.validate` 报错的语法错误，`HostsContentValidator` 必须也拒绝；
/// - `HostsContentValidator` 额外校验（必备系统条目、HostCat 区块标记），不在 `HostsParser` 职责内。
final class ValidatorParityTests: XCTestCase {
    private let writeValidator = HostsContentValidator()
    private let parser = HostsParser()

    private let beginMarker = "# --- HostCat Begin (v1) ---"
    private let endMarker = "# --- HostCat End ---"
    private let requiredEntries = """
    127.0.0.1 localhost
    255.255.255.255 broadcasthost
    ::1 localhost
    """

    /// 构造符合写入校验所有前置条件的有效内容；测试时可以追加额外行。
    private func makeValidWriteContent(extra: String = "") -> String {
        let extraSection = extra.isEmpty ? "" : "\(extra)\n"
        return """
        \(beginMarker)
        \(requiredEntries)
        \(extraSection)\(endMarker)

        """
    }

    // MARK: - parse 通过的内容也能通过写入校验

    func testValidContentPassesBothValidators() throws {
        let content = makeValidWriteContent()

        let parseErrors = parser.validate(content)
        XCTAssertTrue(parseErrors.isEmpty, "有效内容不应有 parse 错误：\(parseErrors)")

        XCTAssertNoThrow(try writeValidator.validate(content),
                         "parse 通过的有效内容也应通过写入校验")
    }

    func testValidContentWithExtraEntriesPassesBothValidators() throws {
        let content = makeValidWriteContent(extra: """
        10.0.0.1 example.com api.example.com
        ::ffff:1.2.3.4 ipv6.example.com
        """)

        let parseErrors = parser.validate(content)
        XCTAssertTrue(parseErrors.isEmpty, "有效内容不应有 parse 错误：\(parseErrors)")
        XCTAssertNoThrow(try writeValidator.validate(content))
    }

    // MARK: - parse 失败的语法错误，写入校验也必须拒绝

    func testInvalidIPRejectedByBothValidators() {
        let content = makeValidWriteContent(extra: "999.999.999.999 bad.example.com")

        let parseErrors = parser.validate(content)
        XCTAssertFalse(parseErrors.isEmpty, "非法 IP 应被 parser 拒绝")
        XCTAssertTrue(parseErrors.contains { error in
            if case .invalidIPAddress = error { return true }
            return false
        })

        XCTAssertThrowsError(try writeValidator.validate(content),
                             "parser 拒绝的非法 IP，写入校验也必须拒绝")
    }

    func testInvalidHostnameRejectedByBothValidators() {
        let content = makeValidWriteContent(extra: "10.0.0.1 bad..hostname")

        let parseErrors = parser.validate(content)
        XCTAssertFalse(parseErrors.isEmpty)
        XCTAssertTrue(parseErrors.contains { error in
            if case .invalidHostname = error { return true }
            return false
        })

        XCTAssertThrowsError(try writeValidator.validate(content))
    }

    func testMissingHostnameRejectedByBothValidators() {
        // 单独一个 IP 没有 hostname
        let content = """
        \(beginMarker)
        \(requiredEntries)
        10.0.0.1
        \(endMarker)

        """

        let parseErrors = parser.validate(content)
        XCTAssertTrue(parseErrors.contains { error in
            if case .missingHostname = error { return true }
            return false
        })

        XCTAssertThrowsError(try writeValidator.validate(content))
    }

    // MARK: - 写入校验的额外职责（parser 不负责）

    /// parse 通过的内容如果缺少必备系统条目，写入校验仍应拒绝；
    /// 这是写入侧的额外职责，不要求 parser 同时报错。
    func testMissingRequiredSystemEntriesOnlyRejectedByWriteValidator() {
        let content = """
        \(beginMarker)
        10.0.0.1 example.com
        \(endMarker)

        """

        let parseErrors = parser.validate(content)
        XCTAssertTrue(parseErrors.isEmpty, "纯语法层面没有错误")

        XCTAssertThrowsError(try writeValidator.validate(content)) { error in
            guard case HostsWriteError.contentValidationFailed = error else {
                XCTFail("应抛 contentValidationFailed，得到：\(error)")
                return
            }
        }
    }

    func testMissingHostCatMarkerOnlyRejectedByWriteValidator() {
        let content = """
        \(requiredEntries)

        """

        let parseErrors = parser.validate(content)
        XCTAssertTrue(parseErrors.isEmpty)

        XCTAssertThrowsError(try writeValidator.validate(content)) { error in
            guard case HostsWriteError.contentValidationFailed = error else {
                XCTFail("应抛 contentValidationFailed，得到：\(error)")
                return
            }
        }
    }

    func testEmptyContentRejectedByWriteValidator() {
        XCTAssertThrowsError(try writeValidator.validate("")) { error in
            guard case HostsWriteError.contentValidationFailed = error else {
                XCTFail("应抛 contentValidationFailed，得到：\(error)")
                return
            }
        }
    }
}
