import XCTest
@testable import HostCatCore

final class HostsImporterTests: XCTestCase {
    func testImportResultIncludesDecodedContentAndCurrentHash() {
        let content = "127.0.0.1 localhost\n::1 localhost\n"

        let result = HostsImporter().importHosts(content)

        XCTAssertEqual(result.decodedContent, content)
        XCTAssertEqual(result.currentHostsHash, HostsHash.sha256Hex(content))
    }

    func testNoHostCatBlockReturnsAllContentAsDefault() {
        let content = "127.0.0.1 localhost\n::1 localhost\n"
        let result = HostsImporter().importHosts(content)

        XCTAssertEqual(result.defaultNodeContent, content)
        XCTAssertFalse(result.hasHostCatBlock)
        XCTAssertNil(result.blockVersion)
        XCTAssertTrue(result.isBlockValid)
        XCTAssertFalse(result.encodingIssue)
    }

    func testCompleteV1BlockExtractsOutsideContent() {
        let outside = "127.0.0.1 localhost\n"
        let inside = "# --- HostCat Begin (v1) ---\n# 默认\n10.0.0.1 api.test\n# --- HostCat End ---"
        let content = outside + inside

        let result = HostsImporter().importHosts(content)

        XCTAssertEqual(result.defaultNodeContent, outside.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertTrue(result.hasHostCatBlock)
        XCTAssertEqual(result.blockVersion, .v1)
        XCTAssertTrue(result.isBlockValid)
        XCTAssertFalse(result.encodingIssue)
    }

    func testMissingBeginMarkerReturnsInvalidBlock() {
        let content = "127.0.0.1 localhost\n# --- HostCat End ---\n"

        let result = HostsImporter().importHosts(content)

        XCTAssertTrue(result.hasHostCatBlock)
        XCTAssertNil(result.blockVersion)
        XCTAssertFalse(result.isBlockValid)
        XCTAssertEqual(result.defaultNodeContent, "127.0.0.1 localhost")
    }

    func testMissingEndMarkerReturnsInvalidBlock() {
        let content = "127.0.0.1 localhost\n# --- HostCat Begin (v1) ---\n10.0.0.1 api.test\n"

        let result = HostsImporter().importHosts(content)

        XCTAssertTrue(result.hasHostCatBlock)
        XCTAssertEqual(result.blockVersion, .v1)
        XCTAssertFalse(result.isBlockValid)
        XCTAssertEqual(result.defaultNodeContent, "127.0.0.1 localhost")
    }

    func testUnknownVersionReturnsInvalidBlock() {
        let content = "127.0.0.1 localhost\n# --- HostCat Begin (v2) ---\n10.0.0.1 api.test\n# --- HostCat End ---"

        let result = HostsImporter().importHosts(content)

        XCTAssertTrue(result.hasHostCatBlock)
        XCTAssertEqual(result.blockVersion, .unknown("v2"))
        XCTAssertFalse(result.isBlockValid)
        XCTAssertEqual(result.defaultNodeContent, "127.0.0.1 localhost")
    }

    func testBlockAtStartExtractsTrailingOutsideContent() {
        let inside = "# --- HostCat Begin (v1) ---\n# 默认\n10.0.0.1 api.test\n# --- HostCat End ---"
        let outside = "\n127.0.0.1 localhost"
        let content = inside + outside

        let result = HostsImporter().importHosts(content)

        XCTAssertEqual(result.defaultNodeContent, "127.0.0.1 localhost")
        XCTAssertTrue(result.hasHostCatBlock)
        XCTAssertTrue(result.isBlockValid)
    }

    func testBlockInMiddleExtractsBothOutsideParts() {
        let before = "127.0.0.1 localhost\n"
        let inside = "# --- HostCat Begin (v1) ---\n# 默认\n10.0.0.1 api.test\n# --- HostCat End ---"
        let after = "\n::1 localhost"
        let content = before + inside + after

        let result = HostsImporter().importHosts(content)

        XCTAssertEqual(result.defaultNodeContent, "127.0.0.1 localhost\n\n::1 localhost")
        XCTAssertTrue(result.hasHostCatBlock)
        XCTAssertTrue(result.isBlockValid)
    }

    func testEmptyOutsideContentReturnsEmptyString() {
        let content = "# --- HostCat Begin (v1) ---\n# 默认\n10.0.0.1 api.test\n# --- HostCat End ---"

        let result = HostsImporter().importHosts(content)

        XCTAssertEqual(result.defaultNodeContent, "")
        XCTAssertTrue(result.hasHostCatBlock)
        XCTAssertTrue(result.isBlockValid)
    }

    func testUTF8DataImport() {
        let content = "127.0.0.1 localhost\n# --- HostCat Begin (v1) ---\n10.0.0.1 api.test\n# --- HostCat End ---"
        let data = Data(content.utf8)

        let result = HostsImporter().importHostsWithFallback(data: data)

        XCTAssertEqual(result.defaultNodeContent, "127.0.0.1 localhost")
        XCTAssertTrue(result.hasHostCatBlock)
        XCTAssertFalse(result.encodingIssue)
    }

    func testLatin1FallbackImportMarksEncodingIssue() {
        var content = "127.0.0.1 localhost\n# --- HostCat Begin (v1) ---\n10.0.0.1 api.test\n# --- HostCat End ---"
        content += "\n# café comment"
        let data = content.data(using: .isoLatin1)!

        let result = HostsImporter().importHostsWithFallback(data: data)

        XCTAssertEqual(result.defaultNodeContent, "127.0.0.1 localhost\n\n# café comment")
        XCTAssertTrue(result.hasHostCatBlock)
        XCTAssertTrue(result.encodingIssue)
    }

    func testLatin1ArbitraryBytesArePreservedWithEncodingIssue() {
        let data = Data([0xFF, 0xFE, 0xFD])

        let result = HostsImporter().importHostsWithFallback(data: data)

        XCTAssertEqual(result.defaultNodeContent, "ÿþý")
        XCTAssertFalse(result.hasHostCatBlock)
        XCTAssertTrue(result.encodingIssue)
    }

    func testWhitespaceAroundMarkersIsHandled() {
        let content = "  127.0.0.1 localhost  \n  # --- HostCat Begin (v1) ---  \n10.0.0.1 api.test\n  # --- HostCat End ---  \n  ::1 localhost  "

        let result = HostsImporter().importHosts(content)

        XCTAssertTrue(result.hasHostCatBlock)
        XCTAssertTrue(result.isBlockValid)
        XCTAssertTrue(result.defaultNodeContent.contains("127.0.0.1 localhost"))
        XCTAssertTrue(result.defaultNodeContent.contains("::1 localhost"))
    }

    func testMultipleBlocksUsesFirstBlock() {
        let firstBlock = "# --- HostCat Begin (v1) ---\n10.0.0.1 api.test\n# --- HostCat End ---"
        let secondBlock = "# --- HostCat Begin (v1) ---\n10.0.0.2 api2.test\n# --- HostCat End ---"
        let content = "127.0.0.1 localhost\n" + firstBlock + "\n::1 localhost\n" + secondBlock

        let result = HostsImporter().importHosts(content)

        XCTAssertTrue(result.hasHostCatBlock)
        XCTAssertEqual(result.blockVersion, .v1)
        XCTAssertTrue(result.isBlockValid)
        XCTAssertTrue(result.defaultNodeContent.contains("127.0.0.1 localhost"))
        XCTAssertTrue(result.defaultNodeContent.contains("::1 localhost"))
        XCTAssertTrue(result.defaultNodeContent.contains("10.0.0.2 api2.test"))
    }

    func testReversedMarkersTreatedAsMissingEnd() {
        let content = "127.0.0.1 localhost\n# --- HostCat End ---\n10.0.0.1 api.test\n# --- HostCat Begin (v1) ---"

        let result = HostsImporter().importHosts(content)

        XCTAssertTrue(result.hasHostCatBlock)
        XCTAssertNil(result.blockVersion)
        XCTAssertFalse(result.isBlockValid)
    }

    func testEmptyFileReturnsEmptyDefaultContent() {
        let content = ""

        let result = HostsImporter().importHosts(content)

        XCTAssertEqual(result.defaultNodeContent, "")
        XCTAssertFalse(result.hasHostCatBlock)
        XCTAssertTrue(result.isBlockValid)
    }

    func testWhitespaceOnlyFileReturnsEmptyDefaultContent() {
        let content = "   \n\t\n   "

        let result = HostsImporter().importHosts(content)

        XCTAssertEqual(result.defaultNodeContent, "")
        XCTAssertFalse(result.hasHostCatBlock)
        XCTAssertTrue(result.isBlockValid)
    }

    func testUTF8DecodeFailureFallsBackToLatin1() {
        let content = "127.0.0.1 localhost\n# --- HostCat Begin (v1) ---\n10.0.0.1 api.test\n# --- HostCat End ---"
        let latin1Data = content.data(using: .isoLatin1)!

        let result = HostsImporter().importHostsWithFallback(data: latin1Data)

        XCTAssertEqual(result.defaultNodeContent, "127.0.0.1 localhost")
        XCTAssertTrue(result.hasHostCatBlock)
        XCTAssertFalse(result.encodingIssue)
    }
}
