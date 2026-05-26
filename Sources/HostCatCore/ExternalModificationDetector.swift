import Foundation

/// Detects external modifications to /etc/hosts outside of HostCat.
public enum ExternalModificationResult: Equatable, Sendable {
    /// No changes detected; hash matches.
    case noChange
    /// File was modified externally (hash mismatch).
    case modified
    /// First run; no expected hash available.
    case firstRun
}

/// Detects whether /etc/hosts was modified outside of HostCat.
public struct ExternalModificationDetector: Sendable {
    public init() {}

    /// Checks whether the current hosts content matches the expected hash.
    ///
    /// - Parameters:
    ///   - expectedHash: The hash recorded after the last successful HostCat write; nil indicates first run.
    ///   - currentHostsContent: The current text content of /etc/hosts.
    /// - Returns: The detection result.
    public func detect(
        expectedHash: String?,
        currentHostsContent: String
    ) -> ExternalModificationResult {
        guard let expectedHash, !expectedHash.isEmpty else {
            return .firstRun
        }

        let currentHash = HostsHash.sha256Hex(currentHostsContent)
        if currentHash == expectedHash {
            return .noChange
        }

        return .modified
    }
}
