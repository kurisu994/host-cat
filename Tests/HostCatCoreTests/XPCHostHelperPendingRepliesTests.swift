import XCTest
@testable import HostCatHelperClient

final class XPCHostHelperPendingRepliesTests: XCTestCase {
    func testCompletingRequestTwiceReturnsValueOnlyOnce() {
        let pendingReplies = XPCHostHelperPendingReplies<String>()
        let requestID = UUID()

        pendingReplies.register("reply", id: requestID)

        XCTAssertEqual(pendingReplies.complete(id: requestID), "reply")
        XCTAssertNil(pendingReplies.complete(id: requestID))
    }

    func testRemoveAllDrainsPendingReplies() {
        let pendingReplies = XPCHostHelperPendingReplies<String>()
        let firstID = UUID()
        let secondID = UUID()

        pendingReplies.register("first", id: firstID)
        pendingReplies.register("second", id: secondID)

        XCTAssertEqual(Set(pendingReplies.removeAll()), ["first", "second"])
        XCTAssertNil(pendingReplies.complete(id: firstID))
        XCTAssertNil(pendingReplies.complete(id: secondID))
    }
}
