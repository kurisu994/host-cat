import Combine
import Foundation
import os.log

/// Node information for menu bar display.
public struct MenuBarNodeItem: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var isActive: Bool
    public var groupID: UUID?

    public init(id: UUID, name: String, isActive: Bool, groupID: UUID? = nil) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.groupID = groupID
    }
}

/// Group information for menu bar display.
public struct MenuBarGroupItem: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var isSingleSelect: Bool
    public var nodes: [MenuBarNodeItem]

    public init(id: UUID, name: String, isSingleSelect: Bool, nodes: [MenuBarNodeItem]) {
        self.id = id
        self.name = name
        self.isSingleSelect = isSingleSelect
        self.nodes = nodes
    }
}

/// Menu bar view model that maintains in-memory config state and interacts with HostWriteCoordinator.
@MainActor
public final class MenuBarViewModel: ObservableObject {
    @Published public var config: AppConfig
    @Published public var applyError: String?
    @Published public var isApplying = false
    @Published public var lastMergedText: String?
    @Published public var lastDuplicateCount: Int = 0
    @Published public var lastConflicts: [HostConflict] = []

    // External modification detection
    @Published public var showExternalModificationAlert = false
    @Published public var externalModificationContent: String?

    // Helper status alert
    @Published public var showHelperRegistrationAlert = false

    private let mutationService = ConfigMutationService()
    private let coordinator: HostWriteCoordinator
    private let configStore: AppConfigStore
    private let logger = Logger(subsystem: "com.hostcat.app", category: "MenuBarViewModel")
    private var applyGeneration = 0

    public init(
        config: AppConfig,
        coordinator: HostWriteCoordinator,
        configStore: AppConfigStore = AppConfigStore()
    ) {
        self.config = config
        self.coordinator = coordinator
        self.configStore = configStore
    }

    // MARK: - Menu Bar Items

    public var defaultNodeItem: MenuBarNodeItem {
        MenuBarNodeItem(
            id: config.defaultNode.id,
            name: config.defaultNode.name,
            isActive: config.defaultNode.isActive
        )
    }

    public var groupItems: [MenuBarGroupItem] {
        config.groups.map { group in
            MenuBarGroupItem(
                id: group.id,
                name: group.name,
                isSingleSelect: group.isSingleSelect,
                nodes: group.nodes.map { node in
                    MenuBarNodeItem(
                        id: node.id,
                        name: node.name,
                        isActive: node.isActive,
                        groupID: group.id
                    )
                }
            )
        }
    }

    // MARK: - Node Activation

    public func toggleNode(id: UUID, inGroup groupID: UUID?) {
        if let groupID = groupID {
            guard let groupIndex = config.groups.firstIndex(where: { $0.id == groupID }) else {
                logger.warning("Attempted to toggle non-existent group: \(groupID.uuidString)")
                return
            }
            guard let nodeIndex = config.groups[groupIndex].nodes.firstIndex(where: { $0.id == id }) else {
                logger.warning("Attempted to toggle non-existent node: \(id.uuidString)")
                return
            }
            let currentActive = config.groups[groupIndex].nodes[nodeIndex].isActive
            let nodeName = config.groups[groupIndex].nodes[nodeIndex].name
            mutationService.setNodeActive(
                id: id,
                active: !currentActive,
                inGroup: groupID,
                in: &config
            )
            logger.info("Node \(nodeName) toggled to \(!currentActive)")
        } else {
            // Default node cannot be deactivated
            logger.debug("Default node toggle ignored")
        }

        // Trigger debounced write
        scheduleApply()
    }

    // MARK: - Apply

    public func scheduleApply() {
        isApplying = true
        applyError = nil
        lastConflicts = []
        let generation = nextApplyGeneration()

        Task {
            guard persistDraftConfig() else {
                finishApplyIfCurrent(generation)
                return
            }

            let (result, rolledBackConfig) = await coordinator.scheduleApply(config: config)
            guard isCurrentApplyGeneration(generation) else {
                return
            }
            isApplying = false
            handleApplyCompletion(result: result, rolledBackConfig: rolledBackConfig, failureLogPrefix: "Write failed")
        }
    }

    public func applyImmediately() async -> ApplyResult {
        isApplying = true
        applyError = nil
        lastConflicts = []
        let generation = nextApplyGeneration()

        guard persistDraftConfig() else {
            finishApplyIfCurrent(generation)
            let message = applyError ?? LC.configSaveFailed
            return ApplyResult(
                success: false,
                errorMessage: message,
                status: .writeFailed(message)
            )
        }

        let (result, rolledBackConfig) = await coordinator.applyImmediately(config: config)

        guard isCurrentApplyGeneration(generation) else {
            return result
        }
        isApplying = false
        handleApplyCompletion(result: result, rolledBackConfig: rolledBackConfig, failureLogPrefix: "Immediate apply failed")

        return result
    }

    /// Restore configuration from hosts backup content; current draft config is not replaced until write succeeds.
    public func restoreBackup(content: String) async -> ApplyResult {
        isApplying = true
        applyError = nil
        lastConflicts = []
        let generation = nextApplyGeneration()

        let importResult = HostsImporter().importHosts(content)
        var restoredConfig = config
        restoredConfig.defaultNode.content = importResult.safeDefaultNodeContent
        for groupIndex in restoredConfig.groups.indices {
            for nodeIndex in restoredConfig.groups[groupIndex].nodes.indices {
                restoredConfig.groups[groupIndex].nodes[nodeIndex].isActive = false
            }
        }

        let (result, rolledBackConfig) = await coordinator.applyImmediately(config: restoredConfig)

        guard isCurrentApplyGeneration(generation) else {
            return result
        }
        isApplying = false

        if result.success {
            config = restoredConfig
        }
        handleApplyCompletion(result: result, rolledBackConfig: rolledBackConfig, failureLogPrefix: "Backup restore failed")

        return result
    }

    /// Force write, skipping hash validation (used after user confirms overwriting external changes).
    public func forceApply() {
        isApplying = true
        applyError = nil
        lastConflicts = []
        let generation = nextApplyGeneration()

        Task {
            guard persistDraftConfig() else {
                finishApplyIfCurrent(generation)
                return
            }

            let (result, rolledBackConfig) = await coordinator.scheduleApply(config: config, force: true)
            guard isCurrentApplyGeneration(generation) else {
                return
            }
            isApplying = false
            handleApplyCompletion(result: result, rolledBackConfig: rolledBackConfig, failureLogPrefix: "Force write failed")
        }
    }

    private func handleApplyCompletion(
        result: ApplyResult,
        rolledBackConfig: AppConfig?,
        failureLogPrefix: String
    ) {
        if !result.success, rolledBackConfig != nil {
            logger.warning("\(failureLogPrefix), keeping current config draft, hosts not applied")
        }

        if result.success {
            if let hash = result.appliedHash {
                config.state.lastAppliedHostsHash = hash
            }
            if let at = result.appliedAt {
                config.state.lastAppliedAt = at
            }
            do {
                try configStore.save(config)
                logger.info("\(LC.logConfigPersistSuccess)")
            } catch {
                logger.error("\(LC.logConfigPersistFailed(error.localizedDescription))")
                applyError = LC.configSaveFailed + ": \(error.localizedDescription)"
            }
            updateMergedPreview()
        } else if let conflicts = result.conflicts {
            lastConflicts = conflicts
            applyError = LC.conflictsDetected(conflicts.count)
            logger.warning("\(LC.logMergeConflicts(count: conflicts.count))")
        } else if let errorMessage = result.errorMessage {
            // Distinguish external modifications from other write errors.
            if case .writeFailed(let msg) = result.status,
               msg == HostHelperClientError.hashMismatch.localizedDescription {
                showExternalModificationAlert = true
                applyError = LC.externalModificationDetected
                logger.warning("\(LC.logExternalModification)")
            } else {
                applyError = LC.hostsNotApplied(errorMessage)
                logger.error("\(LC.logApplyFailed(failureLogPrefix, errorMessage))")
            }
        }
    }

    private func persistDraftConfig() -> Bool {
        do {
            try configStore.save(config)
            logger.info("\(LC.logDraftPersistSuccess)")
            return true
        } catch {
            logger.error("\(LC.logDraftPersistFailed(error.localizedDescription))")
            applyError = LC.configSaveFailed + ": \(error.localizedDescription)"
            return false
        }
    }

    private func nextApplyGeneration() -> Int {
        applyGeneration += 1
        return applyGeneration
    }

    private func isCurrentApplyGeneration(_ generation: Int) -> Bool {
        generation == applyGeneration
    }

    private func finishApplyIfCurrent(_ generation: Int) {
        guard isCurrentApplyGeneration(generation) else { return }
        isApplying = false
    }

    // MARK: - Preview

    public func updateMergedPreview() {
        do {
            let merged = try HostsMerger().merge(config)
            lastMergedText = merged.text
            lastDuplicateCount = merged.duplicateCount
            logger.debug("\(LC.logMergePreview(merged.records.count, merged.duplicateCount))")
        } catch let HostMergeError.conflicts(conflicts) {
            lastConflicts = conflicts
            applyError = LC.conflictsDetected(conflicts.count)
            logger.warning("\(LC.logPreviewConflicts(conflicts.count))")
        } catch {
            applyError = error.localizedDescription
            logger.error("\(LC.logPreviewMergeFailed(error.localizedDescription))")
        }
    }

    public func clearError() {
        applyError = nil
    }
}
