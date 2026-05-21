import Foundation
import os.log

private typealias ApplyOutcome = (result: ApplyResult, rolledBackConfig: AppConfig?)

/// 应用结果状态码，区分不同结果类型
public enum ApplyStatus: Equatable, Sendable {
    case success
    case cancelled          // debounce 取消，非用户主动取消
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
        debounceInterval: Duration = .milliseconds(500)
    ) {
        self.helperClient = helperClient
        self.merger = merger
        self.debounceInterval = debounceInterval
    }

    /// 调度一次 apply 操作。如果当前已有待执行的 debounce，会取消旧任务并重新开始计时。
    /// 返回的 ApplyResult 表示本次 schedule 最终是否成功完成写入。
    public func scheduleApply(config: AppConfig) async -> (result: ApplyResult, rolledBackConfig: AppConfig?) {
        // 取消之前的 debounce 任务
        pendingTask?.cancel()
        pendingGeneration += 1
        let generation = pendingGeneration

        // 如果当前正在写入，创建一个新的 debounce 任务等待当前写入完成
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
                return await self.performWrite(config: config)
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

        // 等待 debounce 任务完成并返回结果
        return await task.value
    }

    /// 立即执行写入，不经过 debounce。用于编辑窗口的 Apply 按钮等需要即时反馈的场景。
    public func applyImmediately(config: AppConfig) async -> (result: ApplyResult, rolledBackConfig: AppConfig?) {
        pendingTask?.cancel()
        pendingTask = nil
        return await performWrite(config: config)
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

    private func performWrite(config: AppConfig) async -> ApplyOutcome {
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

        // 1. 合并配置并执行 parser 校验
        let merged: MergedHosts
        do {
            merged = try merger.merge(config)
            logger.info("合并成功: \(merged.records.count) 条记录, \(merged.duplicateCount) 条重复")
        } catch let HostMergeError.conflicts(conflicts) {
            logger.warning("合并冲突: \(conflicts.count) 个")
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
            logger.error("合并失败: \(message)")
            return (
                ApplyResult(
                    success: false,
                    errorMessage: message,
                    status: .mergeFailed(message)
                ),
                nil
            )
        }

        // 2. 调用 helper client 写入
        do {
            let result = try await helperClient.writeHosts(
                merged.text,
                expectedCurrentHostsHash: config.state.lastAppliedHostsHash
            )

            // 3. 写入成功：更新状态
            let appliedAt = Date()
            var appliedConfig = config
            appliedConfig.state.lastAppliedHostsHash = result.finalHostsHash
            appliedConfig.state.lastAppliedAt = appliedAt

            lastAppliedHash = result.finalHostsHash
            lastAppliedAt = appliedAt
            lastSuccessfulConfigSnapshot = appliedConfig

            logger.info("写入成功, hash: \(result.finalHostsHash.prefix(8))...")

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
            // 4. 写入失败：回滚到上次成功的配置快照
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            logger.error("写入失败: \(message)")
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
