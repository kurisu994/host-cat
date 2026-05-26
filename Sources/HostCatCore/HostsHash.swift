import CryptoKit
import Foundation

public enum HostsHash {
    /// Computes the SHA256 hex hash of a string.
    /// Uses a pre-allocated buffer and a hex lookup table to avoid temporary allocations from String(format:).
    public static func sha256Hex(_ content: String) -> String {
        let digest = SHA256.hash(data: Data(content.utf8))
        let hexDigits = Array("0123456789abcdef")
        var hexString = ""
        hexString.reserveCapacity(64)
        for byte in digest {
            hexString.append(hexDigits[Int(byte >> 4)])
            hexString.append(hexDigits[Int(byte & 0x0F)])
        }
        return hexString
    }
}
