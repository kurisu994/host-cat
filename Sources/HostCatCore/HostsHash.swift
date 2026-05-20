import CryptoKit
import Foundation

public enum HostsHash {
    /// 计算字符串的 SHA256 十六进制哈希值
    /// 使用预分配缓冲区避免 String(format:) 的多次临时对象分配
    public static func sha256Hex(_ content: String) -> String {
        let digest = SHA256.hash(data: Data(content.utf8))
        var hexString = ""
        hexString.reserveCapacity(digest.count * 2)
        for byte in digest {
            hexString.append(String(byte >> 4, radix: 16))
            hexString.append(String(byte & 0x0F, radix: 16))
        }
        return hexString
    }
}
