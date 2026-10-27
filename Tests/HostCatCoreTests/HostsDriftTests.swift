import XCTest
@testable import HostCatCore

final class HostsDriftTests: XCTestCase {
    func testInSyncWhenMergedTextMatchesDisk() {
        let text = "127.0.0.1 localhost\n"
        let drift = HostsDriftChecker.evaluate(
            diskHash: HostsHash.sha256Hex(text),
            lastAppliedHostsHash: "other",
            lastExternalHostsHash: nil,
            mergedText: text
        )
        XCTAssertEqual(drift, .inSync)
    }

    func testUnappliedWhenDiskStillMatchesBaseline() {
        let drift = HostsDriftChecker.evaluate(
            diskHash: "disk",
            lastAppliedHostsHash: "disk",
            lastExternalHostsHash: nil,
            mergedText: "new config"
        )
        XCTAssertEqual(drift, .unapplied)
    }

    func testExternalModificationWhenDiskDiffersFromBaseline() {
        let drift = HostsDriftChecker.evaluate(
            diskHash: "changed",
            lastAppliedHostsHash: "applied",
            lastExternalHostsHash: "older",
            mergedText: "current config"
        )
        XCTAssertEqual(drift, .externallyModified)
    }

    func testContentOverOneMegabyteIsRejected() {
        let content = String(repeating: "a", count: HostsContentValidator.maxContentUTF8Bytes + 1)
        XCTAssertThrowsError(try HostsContentValidator().validate(content)) { error in
            guard case HostsWriteError.contentValidationFailed = error else {
                return XCTFail("期望内容校验失败，实际 \(error)")
            }
        }
    }
}
