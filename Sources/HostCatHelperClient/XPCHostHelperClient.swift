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
        expectedCurrentHostsHash: String?
    ) async throws -> HostHelperWriteResult {
        let contentsNS = contents as NSString
        let hashNS = expectedCurrentHostsHash as NSString?
        let localizationIdentifierNS = AppLanguage.stored()
            .effectiveLocalizationIdentifier() as NSString
        let requestID = UUID()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let pending = PendingReply(continuation: continuation)
                registerPendingReply(pending, id: requestID)
                logger.debug("XPC write request registered: \(requestID.uuidString)")

                guard !Task.isCancelled else {
                    if completePendingReply(requestID, with: .failure(CancellationError())) {
                        logger.warning("XPC write request cancelled before proxy lookup: \(requestID.uuidString)")
                    }
                    return
                }

                let proxy: HostCatHelperXPCProtocol
                do {
                    proxy = try getProxy { [weak self, logger] error in
                        let didComplete = self?.completePendingReply(
                            requestID,
                            with: .failure(HostHelperClientError.unavailable(error.localizedDescription))
                        ) ?? false
                        if didComplete {
                            logger.error("XPC remote object error: \(error.localizedDescription)")
                            self?.invalidateConnection()
                        }
                    }
                } catch {
                    completePendingReply(requestID, with: .failure(error))
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
                    logger.error("XPC write request timed out: \(requestID.uuidString)")
                    self?.invalidateConnection()
                }

                proxy.writeHosts(
                    contentsNS,
                    expectedCurrentHostsHash: hashNS,
                    localizationIdentifier: localizationIdentifierNS
                ) { [weak self, logger] resultDict in
                    do {
                        let result = try Self.parseReply(resultDict, logger: logger)
                        if self?.completePendingReply(requestID, with: .success(result)) == true {
                            logger.info("XPC write request completed: \(requestID.uuidString)")
                        }
                    } catch {
                        if self?.completePendingReply(requestID, with: .failure(error)) == true {
                            logger.error("XPC write request failed while parsing reply: \(error.localizedDescription)")
                        }
                    }
                }
            }
        } onCancel: { [weak self] in
            guard let self else { return }
            if self.completePendingReply(requestID, with: .failure(CancellationError())) {
                self.logger.warning("XPC write request cancelled: \(requestID.uuidString)")
            }
        }
    }

    // MARK: - Connection Management

    /// Gets or creates an XPC proxy.
    private func getProxy(errorHandler: @escaping (Error) -> Void) throws -> HostCatHelperXPCProtocol {
        lock.lock()
        defer { lock.unlock() }

        if let existing = connection {
            // Attempt to reuse an existing connection.
            guard let proxy = existing.remoteObjectProxyWithErrorHandler(errorHandler) as? HostCatHelperXPCProtocol else {
                throw HostHelperClientError.unavailable(LC.helperProxyUnavailable)
            }
            return proxy
        }

        // Create a new connection.
        let newConnection = createConnection()
        connection = newConnection

        guard let proxy = newConnection.remoteObjectProxyWithErrorHandler(errorHandler) as? HostCatHelperXPCProtocol else {
            throw HostHelperClientError.unavailable(LC.helperProxyUnavailable)
        }

        return proxy
    }

    /// Creates an NSXPCConnection.
    private func createConnection() -> NSXPCConnection {
        let conn = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: HostCatHelperXPCProtocol.self)

        // Set Helper-side code signing verification.
        conn.setCodeSigningRequirement(helperRequirement)

        conn.interruptionHandler = { [weak self, logger] in
            logger.warning("XPC connection interrupted")
            self?.failAllPendingReplies(with: HostHelperClientError.connectionInterrupted)
            self?.invalidateConnection()
        }

        conn.invalidationHandler = { [weak self, logger] in
            logger.warning("XPC connection invalidated")
            self?.failAllPendingReplies(with: HostHelperClientError.connectionInvalidated)
            self?.invalidateConnection()
        }

        conn.resume()
        logger.info("XPC connection established: \(self.machServiceName)")
        return conn
    }

    /// Invalidates the existing connection.
    private func invalidateConnection() {
        lock.lock()
        defer { lock.unlock() }
        connection?.invalidate()
        connection = nil
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

    private func failAllPendingReplies(with error: Error) {
        for reply in pendingReplies.removeAll() {
            reply.resume(with: .failure(error))
        }
    }

    // MARK: - Reply Parsing

    /// Parses the NSDictionary returned by the Helper.
    private static func parseReply(
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
                logger.warning("Write succeeded but DNS refresh failed: \(dnsError)")
            }
            logger.info("Helper write reply success, finalHash=\(String(finalHash.prefix(8)))..., didRefreshDNS=\(didRefreshDNS)")

            return HostHelperWriteResult(
                finalHostsHash: finalHash,
                didRefreshDNS: didRefreshDNS
            )
        } else {
            let errorCode = dict["errorCode"] as? String ?? "unknown"
            let errorMessage = dict["errorMessage"] as? String ?? LC.errorUnknown

            logger.error("Helper returned error: code=\(errorCode), message=\(errorMessage)")

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
        lock.lock()
        defer { lock.unlock() }
        let pending = Array(pendingByID.values)
        pendingByID.removeAll()
        return pending
    }
}
