import Foundation
import Testing
@testable import HostCatCore

@Suite("ExternalModificationDetector 测试")
struct ExternalModificationDetectorTests {
    let detector = ExternalModificationDetector()

    @Test("首次运行：expectedHash 为 nil 返回 firstRun")
    func firstRunWithNilHash() {
        let result = detector.detect(
            expectedHash: nil,
            currentHostsContent: "127.0.0.1 localhost"
        )
        #expect(result == .firstRun)
    }

    @Test("首次运行：expectedHash 为空字符串返回 firstRun")
    func firstRunWithEmptyHash() {
        let result = detector.detect(
            expectedHash: "",
            currentHostsContent: "127.0.0.1 localhost"
        )
        #expect(result == .firstRun)
    }

    @Test("无变化：hash 匹配返回 noChange")
    func noChangeWhenHashMatches() {
        let content = "127.0.0.1 localhost\n::1 localhost\n"
        let hash = HostsHash.sha256Hex(content)

        let result = detector.detect(
            expectedHash: hash,
            currentHostsContent: content
        )
        #expect(result == .noChange)
    }

    @Test("外部修改：hash 不匹配返回 modified")
    func modifiedWhenHashDiffers() {
        let oldContent = "127.0.0.1 localhost\n"
        let newContent = "127.0.0.1 localhost\n192.168.1.1 myserver\n"
        let oldHash = HostsHash.sha256Hex(oldContent)

        let result = detector.detect(
            expectedHash: oldHash,
            currentHostsContent: newContent
        )
        #expect(result == .modified)
    }

    @Test("内容完全相同时 hash 匹配")
    func identicalContentMatchesHash() {
        let content = "# System hosts\n127.0.0.1 localhost\n255.255.255.255 broadcasthost\n::1 localhost\n"
        let hash = HostsHash.sha256Hex(content)

        // 用同样内容验证
        let result = detector.detect(
            expectedHash: hash,
            currentHostsContent: content
        )
        #expect(result == .noChange)
    }
}
