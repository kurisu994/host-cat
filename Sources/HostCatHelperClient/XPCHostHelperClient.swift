import Foundation
import HostCatCore
import os.log

/// Real XPC client that communicates with the Privileged Helper via NSXPCConnection.
///
/// Converts XPC reply block patterns into Swift Concurrency `async throws` interfaces;
/// UI and service layers depend only on the `HostHelperClient` protocol.
public final class XPCHostHelperClient: HostHelperClient, @unchecked Sendable {
    private let machServiceName = "com.hostcat.helper"
    private let helperRequirement: String
    private let replyTimeoutNanoseconds: UInt64

    private var connection: NSXPCConnection?
    /// 每新建一条连接加一。连接回调和超时只处理自己那一代，旧连接的回调晚到时不会误伤新连接。
    private var connectionGeneration: UInt64 = 0
    private let pendingReplies = XPCHostHelperPendingReplies<PendingReply>()
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
        expectedCurrentHostsHash: String?,
        force: Bool
    ) async throws -> HostHelperWriteResult {
        let contentsNS = contents as NSString
        let hashNS = expectedCurrentHostsHash as NSString?
        let localizationIdentifierNS = AppLanguage.stored()
            .effectiveLocalizationIdentifier() as NSString
        let requestID = UUID()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let (connection, generation) = currentConnection()
                let pending = PendingReply(continuation: continuation, connectionGeneration: generation)
                registerPendingReply(pending, id: requestID)
                logger.debug("XPC write request registered: \(requestID.uuidString, privacy: .public)")

                guard !Task.isCancelled else {
                    if completePendingReply(requestID, with: .failure(CancellationError())) {
                        logger.warning("XPC write request cancelled before proxy lookup: \(requestID.uuidString, privacy: .public)")
                    }
                    return
                }

                let remoteObject = connection.remoteObjectProxyWithErrorHandler { [weak self, logger] error in
                    let didComplete = self?.completePendingReply(
                        requestID,
                        with: .failure(HostHelperClientError.unavailable(error.localizedDescription))
                    ) ?? false
                    if didComplete {
                        logger.error("XPC remote object error: \(error.localizedDescription, privacy: .public)")
                        self?.invalidateConnection(generation: generation)
                    }
                }
                guard let proxy = remoteObject as? HostCatHelperXPCProtocol else {
                    completePendingReply(
                        requestID,
                        with: .failure(HostHelperClientError.unavailable(LC.helperProxyUnavailable))
                    )
                    return
                }

                Task { [weak self, replyTimeoutNanoseconds, logger] in
                    do {
                        try await Task.sleep(nanoseconds: replyTimeoutNanoseconds)
                    } catch {
                        return
                    }

                    guard self?.completePendingReply(
                        requestID,
                        with: .failure(HostHelperClientError.requestTimedOut)
                    ) == true else {
                        return
                    }
                    logger.error("XPC write request timed out: \(requestID.uuidString, privacy: .public)")
                    self?.invalidateConnection(generation: generation)
                }

                proxy.writeHosts(
                    contentsNS,
                    expectedCurrentHostsHash: hashNS,
                    force: force,
                    localizationIdentifier: localizationIdentifierNS
                ) { [weak self, logger] resultDict in
                    do {
                        let result = try Self.parseReply(resultDict, logger: logger)
                        if self?.completePendingReply(requestID, with: .success(result)) == true {
                            logger.info("XPC write request completed: \(requestID.uuidString, privacy: .public)")
                        }
                    } catch {
                        if self?.completePendingReply(requestID, with: .failure(error)) == true {
                            logger.error("XPC write request failed while parsing reply: \(error.localizedDescription, privacy: .public)")
                        }
                    }
                }
            }
        } onCancel: { [weak self] in
            guard let self else { return }
            if self.completePendingReply(requestID, with: .failure(CancellationError())) {
                self.logger.warning("XPC write request cancelled: \(requestID.uuidString, privacy: .public)")
            }
        }
    }

    // MARK: - Connection Management

    /// 取当前连接，没有就新建；同时返回该连接的代际号。
    private func currentConnection() -> (NSXPCConnection, UInt64) {
        lock.lock()
        defer { lock.unlock() }

        if let connection {
            return (connection, connectionGeneration)
        }

        connectionGeneration += 1
        let newConnection = createConnection(generation: connectionGeneration)
        connection = newConnection
        return (newConnection, connectionGeneration)
    }

    /// Creates an NSXPCConnection.
    private func createConnection(generation: UInt64) -> NSXPCConnection {
        let conn = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: HostCatHelperXPCProtocol.self)

        // Set Helper-side code signing verification.
        conn.setCodeSigningRequirement(helperRequirement)

        conn.interruptionHandler = { [weak self, logger] in
            logger.warning("XPC connection interrupted, generation=\(generation)")
            self?.failPendingReplies(generation: generation, with: HostHelperClientError.connectionInterrupted)
            self?.invalidateConnection(generation: generation)
        }

        conn.invalidationHandler = { [weak self, logger] in
            logger.warning("XPC connection invalidated, generation=\(generation)")
            self?.failPendingReplies(generation: generation, with: HostHelperClientError.connectionInvalidated)
            self?.invalidateConnection(generation: generation)
        }

        conn.resume()
        logger.info("XPC connection established: \(self.machServiceName, privacy: .public), generation=\(generation)")
        return conn
    }

    /// 只失效仍是当前代际的连接；已被替换的旧连接不再影响新连接。
    private func invalidateConnection(generation: UInt64) {
        lock.lock()
        guard generation == connectionGeneration, let current = connection else {
            lock.unlock()
            return
        }
        connection = nil
        lock.unlock()
        current.invalidate()
    }

    private func registerPendingReply(_ pending: PendingReply, id: UUID) {
        pendingReplies.register(pending, id: id)
    }

    @discardableResult
    private func completePendingReply(_ id: UUID, with result: Result<HostHelperWriteResult, Error>) -> Bool {
        guard let pending = pendingReplies.complete(id: id) else {
            return false
        }

        pending.resume(with: result)
        return true
    }

    /// 只让挂在这条连接上的请求失败。
    private func failPendingReplies(generation: UInt64, with error: Error) {
        for reply in pendingReplies.removeAll(where: { $0.connectionGeneration == generation }) {
            reply.resume(with: .failure(error))
        }
    }

    // MARK: - Reply Parsing

    /// Parses the NSDictionary returned by the Helper.
    static func parseReply(
        _ dict: NSDictionary,
        logger: Logger
    ) throws -> HostHelperWriteResult {
        guard let success = dict["success"] as? Bool else {
            throw HostHelperClientError.unexpectedReply(LC.helperReplyMissingSuccess)
        }

        if success {
            guard let finalHash = dict["finalHash"] as? String else {
                throw HostHelperClientError.unexpectedReply(LC.helperReplyMissingFinalHash)
            }
            let didRefreshDNS = dict["didRefreshDNS"] as? Bool ?? false
            let dnsError = dict["dnsRefreshError"] as? String

            if let dnsError, !dnsError.isEmpty {
                logger.warning("Write succeeded but DNS refresh failed: \(dnsError, privacy: .public)")
            }
            logger.info("Helper write reply success, finalHash=\(String(finalHash.prefix(8)), privacy: .public)..., didRefreshDNS=\(didRefreshDNS)")

            return HostHelperWriteResult(
                finalHostsHash: finalHash,
                didRefreshDNS: didRefreshDNS
            )
        } else {
            let errorCode = dict["errorCode"] as? String ?? "unknown"
            let errorMessage = dict["errorMessage"] as? String ?? LC.errorUnknown

            logger.error("Helper returned error: code=\(errorCode, privacy: .public), message=\(errorMessage, privacy: .public)")

            // Helper 能回复说明连接本身正常：写入失败按写入错误上报，
            // 不能归成「Helper 不可用」，否则 UI 会引导用户去重装 Helper。
            switch errorCode {
            case "hashMismatch":
                throw HostHelperClientError.hashMismatch
            case "fileImmutable":
                throw HostHelperClientError.fileImmutable
            case "hashRequired", "invalidHostsPath", "writeFailed":
                throw HostHelperClientError.writeRejected(errorMessage)
            default:
                throw HostHelperClientError.unexpectedReply(errorMessage)
            }
        }
    }

    private final class PendingReply: @unchecked Sendable {
        private let continuation: CheckedContinuation<HostHelperWriteResult, Error>
        let connectionGeneration: UInt64

        init(continuation: CheckedContinuation<HostHelperWriteResult, Error>, connectionGeneration: UInt64) {
            self.continuation = continuation
            self.connectionGeneration = connectionGeneration
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

/// 跟踪 XPC 请求是否仍处于 pending 状态，确保 reply、timeout、取消只会完成一次。
final class XPCHostHelperPendingReplies<Value>: @unchecked Sendable {
    private var pendingByID: [UUID: Value] = [:]
    private let lock = NSLock()

    func register(_ value: Value, id: UUID) {
        lock.lock()
        pendingByID[id] = value
        lock.unlock()
    }

    @discardableResult
    func complete(id: UUID) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return pendingByID.removeValue(forKey: id)
    }

    func removeAll() -> [Value] {
        removeAll(where: { _ in true })
    }

    /// 取出并移除满足条件的 pending 请求。
    func removeAll(where shouldRemove: (Value) -> Bool) -> [Value] {
        lock.lock()
        defer { lock.unlock() }
        let matchedIDs = pendingByID.filter { shouldRemove($0.value) }.map(\.key)
        return matchedIDs.compactMap { pendingByID.removeValue(forKey: $0) }
    }
}
