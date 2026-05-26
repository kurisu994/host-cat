import Foundation
import os.log

private typealias ApplyOutcome = (result: ApplyResult, rolledBackConfig: AppConfig?)
private typealias WritePlan = (merged: MergedHosts, expectedHash: String?)

/// Apply result status codes, distinguishing different result types.
public enum ApplyStatus: Equatable, Sendable {
    case success
    case cancelled          // debounce cancelled, not user-initiated
    case conflicts([HostConflict])
    case writeFailed(String)
    case mergeFailed(String)
}

public struct ApplyResult: Equatable, Sendable {
    public var success: Bool
    public var appliedHash: String?
    public var appliedAt: Date?
    public var conflicts: [HostConflict]?
    public var errorMessage: String?
    public var status: ApplyStatus

    public init(
        success: Bool,
        appliedHash: String? = nil,
        appliedAt: Date? = nil,
        conflicts: [HostConflict]? = nil,
        errorMessage: String? = nil,
        status: ApplyStatus = .success
    ) {
        self.success = success
        self.appliedHash = appliedHash
        self.appliedAt = appliedAt
        self.conflicts = conflicts
        self.errorMessage = errorMessage
        self.status = status
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

    private var pendingTask: Task<ApplyOutcome, Never>?
    private var pendingGeneration = 0
    private var isWriting = false

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
    public func scheduleApply(
        config: AppConfig,
        force: Bool = false
    ) async -> (result: ApplyResult, rolledBackConfig: AppConfig?) {
        // Cancel the previous debounce task.
        pendingTask?.cancel()
        pendingGeneration += 1
        let generation = pendingGeneration

        // If a write is currently in progress, create a new debounce task that waits for it to finish.
        let task = Task<ApplyOutcome, Never> { [debounceInterval] in
            do {
                try await Task.sleep(for: debounceInterval)
                guard !Task.isCancelled else {
                    return (
                        ApplyResult(
                            success: false,
                            status: .cancelled
                        ),
                        nil
                    )
                }

                self.clearPendingTask(ifGeneration: generation)
                return await self.performWrite(config: config, force: force)
            } catch {
                return (
                    ApplyResult(
                        success: false,
                        status: .cancelled
                    ),
                    nil
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
    ) async -> (result: ApplyResult, rolledBackConfig: AppConfig?) {
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

    private func performWrite(config: AppConfig, force: Bool) async -> ApplyOutcome {
        guard await waitUntilCurrentWriteFinishes() else {
            return (
                ApplyResult(
                    success: false,
                    status: .cancelled
                ),
                nil
            )
        }

        isWriting = true
        defer { isWriting = false }

        // 1. Merge config and perform parser validation
        let writePlan: WritePlan
        do {
            let merged = try merger.merge(config)
            let expectedHash = force
                ? nil
                : config.state.lastAppliedHostsHash ?? config.state.lastExternalHostsHash
            writePlan = (merged, expectedHash)
            logger.info(LC.logMergeSuccess(records: merged.records.count, duplicates: merged.duplicateCount))
        } catch let HostMergeError.conflicts(conflicts) {
            logger.warning(LC.logMergeConflicts(count: conflicts.count))
            return (
                ApplyResult(
                    success: false,
                    conflicts: conflicts,
                    status: .conflicts(conflicts)
                ),
                nil
            )
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            logger.error(LC.logMergeFailed(message))
            return (
                ApplyResult(
                    success: false,
                    errorMessage: message,
                    status: .mergeFailed(message)
                ),
                nil
            )
        }

        // 2. Backup current /etc/hosts before writing
        if let backupStore {
            do {
                let currentHostsData = try Data(contentsOf: URL(fileURLWithPath: hostsPath))
                let currentHostsText = HostsImporter().importHostsWithFallback(data: currentHostsData).decodedContent
                _ = try backupStore.createBackup(content: currentHostsText)
                logger.info(LC.logBackupCreated("pre-write"))
            } catch {
                let message = "\(LC.logBackupFailed(error.localizedDescription))"
                logger.error("\(message)")
                return (
                    ApplyResult(
                        success: false,
                        errorMessage: message,
                        status: .writeFailed(message)
                    ),
                    lastSuccessfulConfigSnapshot
                )
            }
        }

        // 3. Call helper client to write
        do {
            let result = try await helperClient.writeHosts(
                writePlan.merged.text,
                expectedCurrentHostsHash: writePlan.expectedHash
            )

            // 4. Write succeeded: update state
            let appliedAt = Date()
            var appliedConfig = config
            appliedConfig.state.lastAppliedHostsHash = result.finalHostsHash
            appliedConfig.state.lastAppliedAt = appliedAt

            lastAppliedHash = result.finalHostsHash
            lastAppliedAt = appliedAt
            lastSuccessfulConfigSnapshot = appliedConfig

            logger.info(LC.logWriteSuccess(hashPrefix: String(result.finalHostsHash.prefix(8))))

            return (
                ApplyResult(
                    success: true,
                    appliedHash: result.finalHostsHash,
                    appliedAt: appliedAt,
                    status: .success
                ),
                nil
            )
        } catch {
            // 5. Write failed: roll back to the last successful config snapshot
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            logger.error(LC.logWriteFailed(message))
            let rolledBack = lastSuccessfulConfigSnapshot
            return (
                ApplyResult(
                    success: false,
                    errorMessage: message,
                    status: .writeFailed(message)
                ),
                rolledBack
            )
        }
    }
}
