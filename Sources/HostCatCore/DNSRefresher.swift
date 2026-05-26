import Foundation

/// Protocol for DNS cache refresh, allowing test injection.
public protocol DNSRefreshing: Sendable {
    func refreshDNSCache() throws
}

/// Real DNS refresher that executes standard macOS flush commands.
///
/// Only two fixed commands are allowed:
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
            throw HostsWriteError.dnsRefreshFailed("Failed to launch \(path): \(error.localizedDescription)")
        }

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stderr = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let command = ([path] + arguments).joined(separator: " ")
            throw HostsWriteError.dnsRefreshFailed("\(command) exited with \(process.terminationStatus): \(stderr)")
        }
    }
}
