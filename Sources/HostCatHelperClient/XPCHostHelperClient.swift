import Foundation
import HostCatCore
import os.log

/// 真实 XPC client，通过 NSXPCConnection 与 Privileged Helper 通信
///
/// 将 XPC reply block 模式转换为 Swift Concurrency `async throws` 接口，
/// UI 和服务层只依赖 `HostHelperClient` 协议。
public final class XPCHostHelperClient: HostHelperClient, @unchecked Sendable {
    private let machServiceName = "com.hostcat.helper"
    // TODO: 部署前替换为真实 Team ID
    private let helperRequirement = "identifier \"com.hostcat.helper\""

    private var connection: NSXPCConnection?
    private let lock = NSLock()
    private let logger = Logger(subsystem: "com.hostcat.app", category: "XPCHostHelperClient")

    public init() {}

    public func writeHosts(
        _ contents: String,
        expectedCurrentHostsHash: String?
    ) async throws -> HostHelperWriteResult {
        let proxy = try getProxy()
        let contentsNS = contents as NSString
        let hashNS = expectedCurrentHostsHash as NSString?

        return try await withCheckedThrowingContinuation { continuation in
            proxy.writeHosts(contentsNS, expectedCurrentHostsHash: hashNS) { [logger] resultDict in
                do {
                    let result = try Self.parseReply(resultDict, logger: logger)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Connection Management

    /// 获取或创建 XPC proxy
    private func getProxy() throws -> HostCatHelperXPCProtocol {
        lock.lock()
        defer { lock.unlock() }

        if let existing = connection {
            // 尝试复用已有连接
            guard let proxy = existing.remoteObjectProxyWithErrorHandler({ [weak self] error in
                self?.logger.error("XPC 远程对象错误: \(error.localizedDescription)")
                self?.invalidateConnection()
            }) as? HostCatHelperXPCProtocol else {
                throw HostHelperClientError.unavailable("无法获取 XPC proxy")
            }
            return proxy
        }

        // 创建新连接
        let newConnection = createConnection()
        connection = newConnection

        guard let proxy = newConnection.remoteObjectProxyWithErrorHandler({ [weak self] error in
            self?.logger.error("XPC 远程对象错误: \(error.localizedDescription)")
            self?.invalidateConnection()
        }) as? HostCatHelperXPCProtocol else {
            throw HostHelperClientError.unavailable("无法获取 XPC proxy")
        }

        return proxy
    }

    /// 创建 NSXPCConnection
    private func createConnection() -> NSXPCConnection {
        let conn = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: HostCatHelperXPCProtocol.self)

        // 设置 Helper 端签名校验
        conn.setCodeSigningRequirement(helperRequirement)

        conn.interruptionHandler = { [weak self, logger] in
            logger.warning("XPC 连接中断")
            self?.invalidateConnection()
        }

        conn.invalidationHandler = { [weak self, logger] in
            logger.warning("XPC 连接失效")
            self?.invalidateConnection()
        }

        conn.resume()
        logger.info("XPC 连接已建立: \(self.machServiceName)")
        return conn
    }

    /// 使已有连接失效
    private func invalidateConnection() {
        lock.lock()
        defer { lock.unlock() }
        connection?.invalidate()
        connection = nil
    }

    // MARK: - Reply Parsing

    /// 解析 Helper 返回的 NSDictionary
    private static func parseReply(
        _ dict: NSDictionary,
        logger: Logger
    ) throws -> HostHelperWriteResult {
        guard let success = dict["success"] as? Bool else {
            throw HostHelperClientError.unexpectedReply("缺少 success 字段")
        }

        if success {
            guard let finalHash = dict["finalHash"] as? String else {
                throw HostHelperClientError.unexpectedReply("成功响应缺少 finalHash")
            }
            let didRefreshDNS = dict["didRefreshDNS"] as? Bool ?? false
            let dnsError = dict["dnsRefreshError"] as? String

            if let dnsError, !dnsError.isEmpty {
                logger.warning("写入成功但 DNS 刷新失败: \(dnsError)")
            }

            return HostHelperWriteResult(
                finalHostsHash: finalHash,
                didRefreshDNS: didRefreshDNS
            )
        } else {
            let errorCode = dict["errorCode"] as? String ?? "unknown"
            let errorMessage = dict["errorMessage"] as? String ?? "未知错误"

            logger.error("Helper 返回错误: code=\(errorCode), message=\(errorMessage)")

            switch errorCode {
            case "hashMismatch":
                throw HostHelperClientError.hashMismatch
            case "fileImmutable":
                throw HostHelperClientError.fileImmutable
            default:
                throw HostHelperClientError.unavailable(errorMessage)
            }
        }
    }
}
