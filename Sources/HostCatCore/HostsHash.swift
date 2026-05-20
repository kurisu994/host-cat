import CryptoKit
import Foundation

public enum HostsHash {
    public static func sha256Hex(_ content: String) -> String {
        let digest = SHA256.hash(data: Data(content.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
