import Foundation

/// DNS 缓存刷新协议，便于测试注入
public protocol DNSRefreshing: Sendable {
    func refreshDNSCache() throws
}

/// 真实 DNS 刷新器，执行 macOS 标准刷新命令
///
/// 只允许两个固定命令：
/// - `dscacheutil -flushcache`
/// - `killall -HUP mDNSResponder`
public struct SystemDNSRefresher: DNSRefreshing, Sendable {
    public init() {}

    public func refreshDNSCache() throws {
        // 1. dscacheutil -flushcache
        try runCommand("/usr/bin/dscacheutil", arguments: ["-flushcache"])
        // 2. killall -HUP mDNSResponder
        try runCommand("/usr/bin/killall", arguments: ["-HUP", "mDNSResponder"])
    }

    private func runCommand(_ path: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw HostsWriteError.dnsRefreshFailed("启动 \(path) 失败：\(error.localizedDescription)")
        }

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stderr = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let command = ([path] + arguments).joined(separator: " ")
            throw HostsWriteError.dnsRefreshFailed("\(command) 返回 \(process.terminationStatus): \(stderr)")
        }
    }
}
