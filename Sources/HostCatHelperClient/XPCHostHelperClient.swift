import Foundation
import HostCatCore
import os.log

/// 真实 XPC client，通过 NSXPCConnection 与 Privileged Helper 通信
///
/// 将 XPC reply block 模式转换为 Swift Concurrency `async throws` 接口，
/// UI 和服务层只依赖 `HostHelperClient` 协议。
public final class XPCHostHelperClient: HostHelperClient, @unchecked Sendable {
    private let machServiceName = "com.hostcat.helper"
    private let helperRequirement: String
    private let replyTimeoutNanoseconds: UInt64

    private var connection: NSXPCConnection?
    private var pendingReplies: [UUID: PendingReply] = [:]
    private let lock = NSLock()
    private let logger = Logger(subsystem: "com.hostcat.app", category: "XPCHostHelperClient")

    public init(
        teamIdentifier: String = HostCatCodeSigningRequirements.teamIdentifier(),
        replyTimeoutNanoseconds: UInt64 = 10_000_000_000
    ) {
        helperRequirement = HostCatCodeSigningRequirements.helperRequirement(teamIdentifier: teamIdentifier)
        self.replyTimeoutNanoseconds = replyTimeoutNanoseconds
    }

    public func writeHosts(
        _ contents: String,
        expectedCurrentHostsHash: String?
    ) async throws -> HostHelperWriteResult {
        let contentsNS = contents as NSString
        let hashNS = expectedCurrentHostsHash as NSString?
        let requestID = UUID()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let pending = PendingReply(continuation: continuation)
                registerPendingReply(pending, id: requestID)

                guard !Task.isCancelled else {
                    completePendingReply(requestID, with: .failure(CancellationError()))
                    return
                }

                let proxy: HostCatHelperXPCProtocol
                do {
                    proxy = try getProxy { [weak self, logger] error in
                        logger.error("XPC 远程对象错误: \(error.localizedDescription)")
                        self?.completePendingReply(
                            requestID,
                            with: .failure(HostHelperClientError.unavailable(error.localizedDescription))
                        )
                        self?.invalidateConnection()
                    }
                } catch {
                    completePendingReply(requestID, with: .failure(error))
                    return
                }

                Task { [weak self, replyTimeoutNanoseconds] in
                    do {
                        try await Task.sleep(nanoseconds: replyTimeoutNanoseconds)
                    } catch {
                        return
                    }

                    self?.completePendingReply(requestID, with: .failure(HostHelperClientError.requestTimedOut))
                    self?.invalidateConnection()
                }

                proxy.writeHosts(contentsNS, expectedCurrentHostsHash: hashNS) { [weak self, logger] resultDict in
                    do {
                        let result = try Self.parseReply(resultDict, logger: logger)
                        self?.completePendingReply(requestID, with: .success(result))
                    } catch {
                        self?.completePendingReply(requestID, with: .failure(error))
                    }
                }
            }
        } onCancel: { [weak self] in
            self?.completePendingReply(requestID, with: .failure(CancellationError()))
        }
    }

    // MARK: - Connection Management

    /// 获取或创建 XPC proxy
    private func getProxy(errorHandler: @escaping (Error) -> Void) throws -> HostCatHelperXPCProtocol {
        lock.lock()
        defer { lock.unlock() }

        if let existing = connection {
            // 尝试复用已有连接
            guard let proxy = existing.remoteObjectProxyWithErrorHandler(errorHandler) as? HostCatHelperXPCProtocol else {
                throw HostHelperClientError.unavailable("无法获取 XPC proxy")
            }
            return proxy
        }

        // 创建新连接
        let newConnection = createConnection()
        connection = newConnection

        guard let proxy = newConnection.remoteObjectProxyWithErrorHandler(errorHandler) as? HostCatHelperXPCProtocol else {
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
            self?.failAllPendingReplies(with: HostHelperClientError.connectionInterrupted)
            self?.invalidateConnection()
        }

        conn.invalidationHandler = { [weak self, logger] in
            logger.warning("XPC 连接失效")
            self?.failAllPendingReplies(with: HostHelperClientError.connectionInvalidated)
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

    private func registerPendingReply(_ pending: PendingReply, id: UUID) {
        lock.lock()
        pendingReplies[id] = pending
        lock.unlock()
    }

    private func completePendingReply(_ id: UUID, with result: Result<HostHelperWriteResult, Error>) {
        lock.lock()
        let pending = pendingReplies.removeValue(forKey: id)
        lock.unlock()

        pending?.resume(with: result)
    }

    private func failAllPendingReplies(with error: Error) {
        lock.lock()
        let pending = Array(pendingReplies.values)
        pendingReplies.removeAll()
        lock.unlock()

        for reply in pending {
            reply.resume(with: .failure(error))
        }
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

    private final class PendingReply: @unchecked Sendable {
        private let continuation: CheckedContinuation<HostHelperWriteResult, Error>

        init(continuation: CheckedContinuation<HostHelperWriteResult, Error>) {
            self.continuation = continuation
        }

        func resume(with result: Result<HostHelperWriteResult, Error>) {
            switch result {
            case let .success(value):
                continuation.resume(returning: value)
            case let .failure(error):
                continuation.resume(throwing: error)
            }
        }
    }
}
