import CryptoKit
import Foundation

public enum HostsHash {
    /// 计算字符串的 SHA256 十六进制哈希值
    /// 使用预分配缓冲区和十六进制查找表，避免 String(format:) 的临时对象分配
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
