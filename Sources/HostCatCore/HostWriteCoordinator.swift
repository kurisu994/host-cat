import Foundation
import os.log

private typealias WritePlan = (merged: MergedHosts, expectedHash: String?)

/// Apply result status codes, distinguishing different result types.
public enum ApplyStatus: Equatable, Sendable {
    case success
    case cancelled          // debounce cancelled, not user-initiated
    case conflicts([HostConflict])
    case writeFailed(String)
    case mergeFailed(String)
    /// 磁盘上的 hosts 与预期 hash 不一致，需要用户决定是否覆盖。
    case hashMismatch
    /// Helper 不可用（未注册、未审批或 XPC 连接断开），UI 应当引导用户去注册/启用 Helper。
    case helperUnavailable(String)
}

public struct ApplyResult: Equatable, Sendable {
    public var success: Bool
    public var appliedHash: String?
    public var appliedAt: Date?
    public var conflicts: [HostConflict]?
    public var errorMessage: String?
    public var status: ApplyStatus
    /// 仅成功时有意义。false 表示文件已写入但 DNS 没确认刷新。
    public var didRefreshDNS: Bool?

    public init(
        success: Bool,
        appliedHash: String? = nil,
        appliedAt: Date? = nil,
        conflicts: [HostConflict]? = nil,
        errorMessage: String? = nil,
        status: ApplyStatus = .success,
        didRefreshDNS: Bool? = nil
    ) {
        self.success = success
        self.appliedHash = appliedHash
        self.appliedAt = appliedAt
        self.conflicts = conflicts
        self.errorMessage = errorMessage
        self.status = status
        self.didRefreshDNS = didRefreshDNS
    }
}

public protocol HostsMerging: Sendable {
    func merge(_ config: AppConfig) throws -> MergedHosts
}

extension HostsMerger: HostsMerging {}

public actor HostWriteCoordinator {
    private let helperClient: HostHelperClient
    private let merger: HostsMerging
    private let backupStore: BackupStore?
    private let hostsPath: String
    private let debounceInterval: Duration
    private let logger = Logger(subsystem: "com.hostcat.app", category: "HostWriteCoordinator")

    private var pendingTask: Task<ApplyResult, Never>?
    private var pendingGeneration = 0
    private var isWriting = false

    /// 最近一次成功写入的配置快照，仅供服务层内部判定真实 hosts 状态，
    /// 不再用于覆盖 UI 的草稿。写入失败时草稿保留在 UI 层，由 `MenuBarViewModel`
    /// 通过 `persistDraftConfig` 在调用 apply 前已经持久化。
    public private(set) var lastSuccessfulConfigSnapshot: AppConfig?
    public private(set) var lastAppliedHash: String?
    public private(set) var lastAppliedAt: Date?

    public init(
        helperClient: HostHelperClient,
        merger: HostsMerging = HostsMerger(),
        backupStore: BackupStore? = BackupStore(),
        hostsPath: String = "/etc/hosts",
        debounceInterval: Duration = .milliseconds(500)
    ) {
        self.helperClient = helperClient
        self.merger = merger
        self.backupStore = backupStore
        self.hostsPath = hostsPath
        self.debounceInterval = debounceInterval
    }

    /// Schedules an apply operation. If a pending debounce exists, the old task is cancelled and restarted.
    /// The returned ApplyResult indicates whether the scheduled write completed successfully.
    /// 失败时不返回回滚快照：UI 在调用前已持久化草稿，hosts 保持未应用状态。
    public func scheduleApply(
        config: AppConfig,
        force: Bool = false
    ) async -> ApplyResult {
        // Cancel the previous debounce task.
        pendingTask?.cancel()
        pendingGeneration += 1
        let generation = pendingGeneration

        // If a write is currently in progress, create a new debounce task that waits for it to finish.
        let task = Task<ApplyResult, Never> { [debounceInterval] in
            do {
                try await Task.sleep(for: debounceInterval)
                guard !Task.isCancelled else {
                    return ApplyResult(
                        success: false,
                        status: .cancelled
                    )
                }

                self.clearPendingTask(ifGeneration: generation)
                return await self.performWrite(config: config, force: force)
            } catch {
                return ApplyResult(
                    success: false,
                    status: .cancelled
                )
            }
        }

        pendingTask = task

        // Wait for the debounce task to complete and return the result.
        return await task.value
    }

    /// Executes the write immediately without debouncing. Used for scenarios requiring instant feedback, such as the Apply button in the editor window.
    public func applyImmediately(
        config: AppConfig,
        force: Bool = false
    ) async -> ApplyResult {
        pendingTask?.cancel()
        pendingTask = nil
        return await performWrite(config: config, force: force)
    }

    // MARK: - Private

    private func clearPendingTask(ifGeneration generation: Int) {
        if pendingGeneration == generation {
            pendingTask = nil
        }
    }

    private func waitUntilCurrentWriteFinishes() async -> Bool {
        while isWriting {
            do {
                try await Task.sleep(for: .milliseconds(10))
            } catch {
                return false
            }

            if Task.isCancelled {
                return false
            }
        }

        return true
    }

    private func performWrite(config: AppConfig, force: Bool) async -> ApplyResult {
        guard await waitUntilCurrentWriteFinishes() else {
            return ApplyResult(
                success: false,
                status: .cancelled
            )
        }

        isWriting = true
        defer { isWriting = false }

        // 1. Merge config and perform parser validation
        let writePlan: WritePlan
        do {
            let merged = try merger.merge(config)
            // 配置快照可能在上一次写入完成前生成，state 里的 hash 会落后于磁盘；
            // 本会话内成功写入过时以 coordinator 自己记录的 hash 为准。
            let expectedHash = force
                ? nil
                : lastAppliedHash ?? config.state.lastAppliedHostsHash ?? config.state.lastExternalHostsHash
            writePlan = (merged, expectedHash)
            logger.info("\(LC.logMergeSuccess(records: merged.records.count, duplicates: merged.duplicateCount), privacy: .public)")
        } catch let HostMergeError.conflicts(conflicts) {
            logger.warning("\(LC.logMergeConflicts(count: conflicts.count), privacy: .public)")
            return ApplyResult(
                success: false,
                conflicts: conflicts,
                status: .conflicts(conflicts)
            )
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            logger.error("\(LC.logMergeFailed(message), privacy: .public)")
            return ApplyResult(
                success: false,
                errorMessage: message,
                status: .mergeFailed(message)
            )
        }

        // 2. Backup current /etc/hosts before writing
        if let backupStore {
            do {
                let currentHostsData = try Data(contentsOf: URL(fileURLWithPath: hostsPath))
                let currentHostsText = HostsImporter().importHostsWithFallback(data: currentHostsData).decodedContent
                _ = try backupStore.createBackup(content: currentHostsText)
                logger.info("\(LC.logBackupCreated("pre-write"), privacy: .public)")
            } catch {
                let message = "\(LC.logBackupFailed(error.localizedDescription))"
                logger.error("\(message, privacy: .public)")
                return ApplyResult(
                    success: false,
                    errorMessage: message,
                    status: .writeFailed(message)
                )
            }
        }

        // 3. Call helper client to write
        do {
            let result = try await helperClient.writeHosts(
                writePlan.merged.text,
                expectedCurrentHostsHash: writePlan.expectedHash,
                force: force
            )

            logger.info("\(LC.logWriteSuccess(hashPrefix: String(result.finalHostsHash.prefix(8))), privacy: .public)")
            return successResult(
                config: config,
                hash: result.finalHostsHash,
                didRefreshDNS: result.didRefreshDNS
            )
        } catch {
            // 超时后 Helper 可能已经写完。磁盘内容和本次合成一致时按成功记，避免下次被误判成外部修改。
            if let helperError = error as? HostHelperClientError,
               case .requestTimedOut = helperError,
               await diskContains(writePlan.merged.text) {
                logger.warning("XPC 超时，但磁盘内容已与本次写入一致，按成功处理")
                return successResult(
                    config: config,
                    hash: HostsHash.sha256Hex(writePlan.merged.text),
                    didRefreshDNS: false
                )
            }

            // 5. Write failed: 草稿已在 UI 层持久化，hosts 保持未应用状态。
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            logger.error("\(LC.logWriteFailed(message), privacy: .public)")
            return ApplyResult(
                success: false,
                errorMessage: message,
                status: Self.status(for: error, message: message)
            )
        }
    }

    private func successResult(config: AppConfig, hash: String, didRefreshDNS: Bool?) -> ApplyResult {
        let appliedAt = Date()
        var appliedConfig = config
        appliedConfig.state.lastAppliedHostsHash = hash
        appliedConfig.state.lastAppliedAt = appliedAt
        lastAppliedHash = hash
        lastAppliedAt = appliedAt
        lastSuccessfulConfigSnapshot = appliedConfig
        return ApplyResult(
            success: true,
            appliedHash: hash,
            appliedAt: appliedAt,
            status: .success,
            didRefreshDNS: didRefreshDNS
        )
    }

    /// 短暂重读几次，覆盖「超时瞬间写入刚好完成」的窗口。
    private func diskContains(_ content: String) async -> Bool {
        let expected = HostsHash.sha256Hex(content)
        for attempt in 0..<4 {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: hostsPath)) else {
                continue
            }
            if HostsHash.sha256Hex(Self.decodeHostsData(data)) == expected {
                return true
            }
        }
        return false
    }

    private static func decodeHostsData(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        return ""
    }

    private static func status(for error: Error, message: String) -> ApplyStatus {
        guard let helperError = error as? HostHelperClientError else {
            return .writeFailed(message)
        }
        switch helperError {
        case .unavailable,
             .helperNotRegistered,
             .helperNotApproved,
             .connectionInterrupted,
             .connectionInvalidated:
            return .helperUnavailable(message)
        case .hashMismatch:
            return .hashMismatch
        case .fileImmutable,
             .requestTimedOut,
             .unexpectedReply,
             .writeRejected:
            return .writeFailed(message)
        }
    }

}
