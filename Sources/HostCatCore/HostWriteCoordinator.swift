import Foundation

public struct ApplyResult: Equatable, Sendable {
    public var success: Bool
    public var appliedHash: String?
    public var appliedAt: Date?
    public var conflicts: [HostConflict]?
    public var errorMessage: String?

    public init(
        success: Bool,
        appliedHash: String? = nil,
        appliedAt: Date? = nil,
        conflicts: [HostConflict]? = nil,
        errorMessage: String? = nil
    ) {
        self.success = success
        self.appliedHash = appliedHash
        self.appliedAt = appliedAt
        self.conflicts = conflicts
        self.errorMessage = errorMessage
    }
}

public actor HostWriteCoordinator {
    private let helperClient: HostHelperClient
    private let debounceInterval: Duration

    private var pendingTask: Task<ApplyResult, Never>?
    private var isWriting = false

    public private(set) var lastSuccessfulConfigSnapshot: AppConfig?
    public private(set) var lastAppliedHash: String?
    public private(set) var lastAppliedAt: Date?

    public init(
        helperClient: HostHelperClient,
        debounceInterval: Duration = .milliseconds(500)
    ) {
        self.helperClient = helperClient
        self.debounceInterval = debounceInterval
    }

    /// 调度一次 apply 操作。如果当前已有待执行的 debounce，会取消旧任务并重新开始计时。
    /// 返回的 ApplyResult 表示本次 schedule 最终是否成功完成写入。
    public func scheduleApply(config: AppConfig) async -> ApplyResult {
        // 取消之前的 debounce 任务
        pendingTask?.cancel()

        // 如果当前正在写入，创建一个新的 debounce 任务等待当前写入完成
        let task = Task { [debounceInterval] in
            do {
                try await Task.sleep(for: debounceInterval)
                guard !Task.isCancelled else {
                    return ApplyResult(success: false, errorMessage: "已取消")
                }

                return await self.performWrite(config: config)
            } catch {
                return ApplyResult(success: false, errorMessage: "已取消")
            }
        }

        pendingTask = task

        // 等待 debounce 任务完成并返回结果
        return await task.value
    }

    /// 立即执行写入，不经过 debounce。用于编辑窗口的 Apply 按钮等需要即时反馈的场景。
    public func applyImmediately(config: AppConfig) async -> ApplyResult {
        pendingTask?.cancel()
        return await performWrite(config: config)
    }

    // MARK: - Private

    private func performWrite(config: AppConfig) async -> ApplyResult {
        isWriting = true
        defer { isWriting = false }

        // 1. 合并配置并执行 parser 校验
        let merged: MergedHosts
        do {
            merged = try HostsMerger().merge(config)
        } catch let HostMergeError.conflicts(conflicts) {
            return ApplyResult(success: false, conflicts: conflicts)
        } catch {
            return ApplyResult(
                success: false,
                errorMessage: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }

        // 2. 调用 helper client 写入
        do {
            let result = try await helperClient.writeHosts(
                merged.text,
                expectedCurrentHostsHash: config.state.lastAppliedHostsHash
            )

            // 3. 写入成功：更新状态
            lastAppliedHash = result.finalHostsHash
            lastAppliedAt = Date()
            lastSuccessfulConfigSnapshot = config

            return ApplyResult(success: true, appliedHash: result.finalHostsHash, appliedAt: lastAppliedAt)
        } catch {
            // 4. 写入失败：只回滚当前失败批次，保留写入期间的新操作
            return ApplyResult(
                success: false,
                errorMessage: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }
}
