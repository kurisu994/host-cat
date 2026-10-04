import AppKit
import HostCatCore
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @State private var selectedNodeID: UUID?
    @State private var editingContent: String = ""
    @State private var errorLines: Set<Int> = []
    @State private var editingName: String = ""
    @State private var showDeleteConfirmation = false
    @State private var nodeToDelete: (groupID: UUID, nodeID: UUID)?
    @State private var showDeleteGroupConfirmation = false
    @State private var groupToDelete: UUID?
    @State private var showAddGroupDialog = false
    @State private var newGroupName: String = ""
    @State private var showAddNodeDialog = false
    @State private var newNodeName: String = ""
    @State private var selectedGroupForNewNode: UUID?
    @State private var showRenameNodeDialog = false
    @State private var editingNodeToRename: (groupID: UUID, nodeID: UUID)?
    @State private var renameNodeNewName: String = ""
    @State private var mutationService = ConfigMutationService()
    @State private var draggingNodeID: UUID?
    @State private var collapsedGroupIDs: Set<UUID> = []
    @State private var searchText: String = ""
    /// 语法校验防抖任务。大文件下逐键全量校验会卡住主线程。
    @State private var validationTask: Task<Void, Never>?

    /// 搜索是否激活。
    private var isSearching: Bool { !searchText.isEmpty }

    /// 默认节点是否通过搜索过滤（无搜索时始终显示）。
    private var showDefaultNode: Bool {
        guard isSearching else { return true }
        let query = searchText
        return viewModel.config.defaultNode.name.localizedCaseInsensitiveContains(query)
            || viewModel.config.defaultNode.content.localizedCaseInsensitiveContains(query)
    }

    /// 过滤后的分组列表（保持树状结构）。
    private var filteredGroups: [HostGroup] {
        guard isSearching else { return viewModel.config.groups }
        let query = searchText
        return viewModel.config.groups.compactMap { group in
            // 分组名匹配 → 展示整个分组
            if group.name.localizedCaseInsensitiveContains(query) {
                return group
            }
            // 否则只保留匹配的节点
            let matched = group.nodes.filter { node in
                node.name.localizedCaseInsensitiveContains(query)
                    || node.content.localizedCaseInsensitiveContains(query)
            }
            return matched.isEmpty
                ? nil
                : HostGroup(id: group.id, name: group.name, isSingleSelect: group.isSingleSelect, nodes: matched)
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Left: groups and node tree
                List(selection: $selectedNodeID) {
                    if showDefaultNode {
                        // Default node
                        Section(L.sidebarDefault) {
                            NodeRow(
                                name: viewModel.config.defaultNode.name,
                                isActive: viewModel.config.defaultNode.isActive,
                                isDefault: true,
                                isSelected: selectedNodeID == viewModel.config.defaultNode.id,
                                onSelect: { selectedNodeID = viewModel.config.defaultNode.id }
                            )
                            .tag(viewModel.config.defaultNode.id)
                        }
                    }

                    if filteredGroups.isEmpty && !showDefaultNode {
                        // 搜索无结果
                        ContentUnavailableView(
                            L.sidebarNoResults,
                            systemImage: "magnifyingglass",
                            description: Text(L.sidebarNoResultsHint)
                        )
                        .listRowSeparator(.hidden)
                    }

                    // Groups (supports drag-and-drop reordering)
                    ForEach(filteredGroups) { group in
                        Section(header: GroupHeader(
                            name: group.name,
                            isCollapsed: collapsedGroupIDs.contains(group.id),
                            onToggleCollapse: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if collapsedGroupIDs.contains(group.id) {
                                        collapsedGroupIDs.remove(group.id)
                                    } else {
                                        collapsedGroupIDs.insert(group.id)
                                    }
                                }
                            },
                            onRename: { newName in
                                let service = mutationService
                                service.renameGroup(id: group.id, to: newName, in: &viewModel.config)
                                viewModel.scheduleApply()
                            },
                            onDelete: {
                                groupToDelete = group.id
                                showDeleteGroupConfirmation = true
                            }
                        )) {
                            if isSearching || !collapsedGroupIDs.contains(group.id) {
                                ForEach(group.nodes) { node in
                                    NodeRow(
                                        name: node.name,
                                        isActive: node.isActive,
                                        isDefault: false,
                                        isSelected: selectedNodeID == node.id,
                                        onToggleActive: {
                                            selectedNodeID = node.id
                                            viewModel.toggleNode(id: node.id, inGroup: group.id)
                                        },
                                        onSelect: { selectedNodeID = node.id }
                                    )
                                    .tag(node.id)
                                    .contextMenu {
                                        Button(L.sidebarRenameNode) {
                                            editingNodeToRename = (group.id, node.id)
                                            renameNodeNewName = node.name
                                            showRenameNodeDialog = true
                                        }
                                        Button(L.sidebarDeleteNode) {
                                            nodeToDelete = (group.id, node.id)
                                            showDeleteConfirmation = true
                                        }
                                    }
                                    .opacity(draggingNodeID == node.id ? 0.4 : 1.0)
                                    .onDrag {
                                        draggingNodeID = node.id
                                        return NSItemProvider(object: node.id.uuidString as NSString)
                                    }
                                    .onDrop(
                                        of: [UTType.text],
                                        delegate: NodeReorderDropDelegate(
                                            targetNodeID: node.id,
                                            groupID: group.id,
                                            draggingNodeID: $draggingNodeID,
                                            viewModel: viewModel
                                        )
                                    )
                                }

                                AddNodeButton {
                                    selectedGroupForNewNode = group.id
                                    newNodeName = ""
                                    showAddNodeDialog = true
                                }
                            }
                        }
                    }
                    .onMove { source, destination in
                        // 搜索结果的下标不是完整分组列表，按它排序会把真实顺序打乱。
                        guard !isSearching else { return }
                        moveGroups(from: source, to: destination)
                    }
                }
                .listStyle(.sidebar)
                .searchable(text: $searchText, prompt: L.sidebarSearchPlaceholder)
                .onAppear {
                    // 打开编辑器就进入默认节点，避免停在「请选择节点」。
                    if selectedNodeID == nil {
                        selectedNodeID = viewModel.config.defaultNode.id
                    }
                    loadNodeContent(id: selectedNodeID)
                }
                .onChange(of: selectedNodeID) { _, newID in
                    loadNodeContent(id: newID)
                }

                Divider()

                SidebarAddGroupButton {
                    newGroupName = ""
                    showAddGroupDialog = true
                }
            }
            .frame(minWidth: 200)
        } detail: {
            // Right: hosts text editor
            if let nodeID = selectedNodeID {
                VStack(alignment: .leading, spacing: 0) {
                    EditorToolbar(
                        viewModel: viewModel,
                        title: editingName,
                        hasUnsavedEdits: hasUnsavedEdits,
                        onImported: refreshAfterImport,
                        onApply: saveCurrentNode,
                        onRevert: {
                            reloadContent(id: nodeID)
                        }
                    )
                    Divider()

                    // Text editor (bridged NSTextView with syntax highlighting and line numbers)
                    HostsTextView(text: $editingContent, errorLines: errorLines)
                        .frame(minWidth: 400, minHeight: 300)
                        .onChange(of: editingContent) { _, newValue in
                            scheduleValidation(newValue)
                        }

                    // Status bar
                    HStack {
                        if viewModel.isApplying {
                            ProgressView()
                                .controlSize(.small)
                            Text(L.editorApplying)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let error = viewModel.applyError {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Spacer()

                        if !errorLines.isEmpty {
                            Label(L.editorSyntaxErrorsCount(errorLines.count), systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        Text(L.editorCharactersCount(editingContent.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                }
            } else {
                ContentUnavailableView(L.editorSelectNode, systemImage: "doc.text")
            }
        }
        .alert(L.dialogDeleteNodeTitle, isPresented: $showDeleteConfirmation) {
            Button(L.dialogDelete, role: .destructive) {
                if let (groupID, nodeID) = nodeToDelete {
                    if selectedNodeID == nodeID {
                        selectedNodeID = nil
                    }
                    let service = mutationService
                    service.removeNode(id: nodeID, fromGroup: groupID, in: &viewModel.config)
                    viewModel.scheduleApply()
                }
                nodeToDelete = nil
            }
            Button(L.dialogCancel, role: .cancel) {
                nodeToDelete = nil
            }
        } message: {
            Text(L.dialogDeleteNodeMessage)
        }
        .alert(L.dialogDeleteGroupTitle, isPresented: $showDeleteGroupConfirmation) {
            Button(L.dialogDelete, role: .destructive) {
                if let groupID = groupToDelete {
                    if let selectedNodeID,
                       viewModel.config.groups.first(where: { $0.id == groupID })?.nodes.contains(where: { $0.id == selectedNodeID }) == true {
                        self.selectedNodeID = nil
                    }
                    let service = mutationService
                    service.removeGroup(id: groupID, from: &viewModel.config)
                    viewModel.scheduleApply()
                }
                groupToDelete = nil
            }
            Button(L.dialogCancel, role: .cancel) {
                groupToDelete = nil
            }
        } message: {
            Text(L.dialogDeleteGroupMessage)
        }
        .frame(minWidth: 700, minHeight: 500)
        .overlay {
            if showAddGroupDialog {
                NameInputDialog(
                    title: L.sidebarAddGroup,
                    placeholder: L.dialogNamePlaceholder,
                    confirmTitle: L.dialogAdd,
                    name: $newGroupName,
                    onCancel: {
                        newGroupName = ""
                        showAddGroupDialog = false
                    },
                    onSubmit: {
                        guard !newGroupName.isEmpty else { return }
                        let service = mutationService
                        service.addGroup(named: newGroupName, to: &viewModel.config)
                        viewModel.scheduleApply()
                        newGroupName = ""
                        showAddGroupDialog = false
                    }
                )
            } else if showAddNodeDialog {
                NameInputDialog(
                    title: L.sidebarAddNode,
                    placeholder: L.dialogNamePlaceholder,
                    confirmTitle: L.dialogAdd,
                    name: $newNodeName,
                    onCancel: {
                        newNodeName = ""
                        selectedGroupForNewNode = nil
                        showAddNodeDialog = false
                    },
                    onSubmit: {
                        guard !newNodeName.isEmpty, let groupID = selectedGroupForNewNode else { return }
                        let service = mutationService
                        service.addNode(named: newNodeName, content: "", toGroup: groupID, in: &viewModel.config)
                        viewModel.scheduleApply()
                        newNodeName = ""
                        selectedGroupForNewNode = nil
                        showAddNodeDialog = false
                    }
                )
            } else if showRenameNodeDialog {
                NameInputDialog(
                    title: L.sidebarRenameNode,
                    placeholder: L.dialogNamePlaceholder,
                    confirmTitle: L.dialogRename,
                    name: $renameNodeNewName,
                    onCancel: {
                        renameNodeNewName = ""
                        editingNodeToRename = nil
                        showRenameNodeDialog = false
                    },
                    onSubmit: {
                        guard !renameNodeNewName.isEmpty,
                              let (groupID, nodeID) = editingNodeToRename else { return }
                        let service = mutationService
                        service.renameNode(id: nodeID, to: renameNodeNewName, inGroup: groupID, in: &viewModel.config)
                        viewModel.scheduleApply()
                        renameNodeNewName = ""
                        editingNodeToRename = nil
                        showRenameNodeDialog = false
                    }
                )
            }
        }
    }

    /// 导入配置后，选中节点可能已被替换或不存在，需重新同步编辑区。
    private func refreshAfterImport() {
        if let id = selectedNodeID, currentNodeContent(id: id) == nil {
            selectedNodeID = nil
        } else {
            loadNodeContent(id: selectedNodeID)
        }
    }

    private func loadNodeContent(id: UUID?) {
        validationTask?.cancel()
        guard let id = id else {
            editingContent = ""
            editingName = ""
            validateContent("")
            return
        }

        if id == viewModel.config.defaultNode.id {
            editingContent = viewModel.config.defaultNode.content
            editingName = viewModel.config.defaultNode.name
            validateContent(editingContent)
            return
        }

        for group in viewModel.config.groups {
            if let node = group.nodes.first(where: { $0.id == id }) {
                editingContent = node.content
                editingName = node.name
                validateContent(editingContent)
                return
            }
        }

        editingContent = ""
        editingName = ""
        validateContent("")
    }

    private var hasUnsavedEdits: Bool {
        guard let id = selectedNodeID, let currentContent = currentNodeContent(id: id) else {
            return false
        }

        return editingContent != currentContent
    }

    private func currentNodeContent(id: UUID) -> String? {
        if id == viewModel.config.defaultNode.id {
            return viewModel.config.defaultNode.content
        }

        for group in viewModel.config.groups {
            if let node = group.nodes.first(where: { $0.id == id }) {
                return node.content
            }
        }

        return nil
    }

    /// Revert only resets the edited content without affecting the node name.
    private func reloadContent(id: UUID) {
        if id == viewModel.config.defaultNode.id {
            editingContent = viewModel.config.defaultNode.content
            return
        }

        for group in viewModel.config.groups {
            if let node = group.nodes.first(where: { $0.id == id }) {
                editingContent = node.content
                return
            }
        }
    }

    private func saveCurrentNode() {
        guard let id = selectedNodeID else { return }
        let service = mutationService

        if id == viewModel.config.defaultNode.id {
            service.updateDefaultNodeContent(editingContent, in: &viewModel.config)
        } else {
            for group in viewModel.config.groups {
                if group.nodes.contains(where: { $0.id == id }) {
                    service.updateNodeContent(id: id, content: editingContent, inGroup: group.id, in: &viewModel.config)
                    break
                }
            }
        }

        viewModel.scheduleApply()
    }

    /// 停止输入约 200ms 后再做全量语法校验，避免超大 hosts 逐键卡顿。
    private func scheduleValidation(_ content: String) {
        validationTask?.cancel()
        validationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            validateContent(content)
        }
    }

    /// Validates edited content and extracts all error line numbers.
    private func validateContent(_ content: String) {
        let parser = HostsParser()
        let errors = parser.validate(content)
        var lines = Set<Int>()
        for error in errors {
            switch error {
            case .invalidIPAddress(let line, _),
                 .missingHostname(let line),
                 .invalidHostname(let line, _):
                lines.insert(line)
            case .emptyContent:
                break
            }
        }
        errorLines = lines
    }

    private func moveGroups(from source: IndexSet, to destination: Int) {
        viewModel.config.groups.move(fromOffsets: source, toOffset: destination)
        viewModel.scheduleApply()
    }
}

private struct EditorToolbar: View {
    private static let titleLeadingInset: CGFloat = 56

    @ObservedObject var viewModel: MenuBarViewModel
    let title: String
    let hasUnsavedEdits: Bool
    let onImported: () -> Void
    let onApply: () -> Void
    let onRevert: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(title.isEmpty ? L.dialogNamePlaceholder : title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 16)

            ConfigTransferMenu(
                viewModel: viewModel,
                hasUnsavedEdits: hasUnsavedEdits,
                onApplyEdits: onApply,
                onDiscardEdits: onRevert,
                onImported: onImported
            )

            Button {
                onRevert()
            } label: {
                Label(L.editorDiscard, systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .help(L.editorDiscardTooltip)
            .accessibilityHint(L.editorDiscardTooltip)
            .disabled(!hasUnsavedEdits)

            Button {
                onApply()
            } label: {
                Label(L.editorApply, systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .keyboardShortcut(.return, modifiers: .command)
            .help(L.editorApplyTooltip)
            .accessibilityHint(L.editorApplyTooltip)
            .disabled(!hasUnsavedEdits)
        }
        .padding(.leading, Self.titleLeadingInset)
        .padding(.trailing, 16)
        .frame(height: 52)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
