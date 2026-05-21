import Foundation
@testable import HostCatCore

// 用于测试的 fake helper client
actor FakeHostHelperClient: HostHelperClient {
    var shouldSucceed: Bool = true
    var simulatedError: Error?
    var writtenContents: [String] = []
    var expectedHashes: [String?] = []
    var delayNanoseconds: UInt64 = 0

    func writeHosts(_ contents: String, expectedCurrentHostsHash: String?) async throws -> HostHelperWriteResult {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        if !shouldSucceed {
            if let error = simulatedError {
                throw error
            } else {
                throw HostHelperClientError.unavailable("模拟写入失败")
            }
        }

        writtenContents.append(contents)
        expectedHashes.append(expectedCurrentHostsHash)
        return HostHelperWriteResult(
            finalHostsHash: HostsHash.sha256Hex(contents),
            didRefreshDNS: true
        )
    }
}

extension FakeHostHelperClient {
    func setShouldSucceed(_ value: Bool) async {
        shouldSucceed = value
    }

    func setSimulatedError(_ error: Error?) async {
        simulatedError = error
    }

    func setDelayNanoseconds(_ value: UInt64) async {
        delayNanoseconds = value
    }
}
