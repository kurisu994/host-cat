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

    /// 旧连接失效时只能让挂在它上面的请求失败，新连接上的请求要保留。
    func testRemoveAllWhereOnlyDrainsMatchingReplies() {
        let pendingReplies = XPCHostHelperPendingReplies<(generation: Int, name: String)>()
        let oldID = UUID()
        let newID = UUID()

        pendingReplies.register((1, "old"), id: oldID)
        pendingReplies.register((2, "new"), id: newID)

        let removed = pendingReplies.removeAll(where: { $0.generation == 1 })

        XCTAssertEqual(removed.map(\.name), ["old"])
        XCTAssertNil(pendingReplies.complete(id: oldID))
        XCTAssertEqual(pendingReplies.complete(id: newID)?.name, "new")
    }
}
