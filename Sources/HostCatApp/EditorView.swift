import AppKit
import HostCatCore
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @State private var selectedNodeID: UUID?
    @State private var editingContent: String = ""
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

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // 左侧：分组和节点树
                List {
                    // 默认节点
                    Section("默认") {
                        NodeRow(
                            name: viewModel.config.defaultNode.name,
                            isActive: viewModel.config.defaultNode.isActive,
                            isDefault: true,
                            isSelected: selectedNodeID == viewModel.config.defaultNode.id
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedNodeID = viewModel.config.defaultNode.id
                        }
                    }

                    // 分组（支持拖拽排序）
                    ForEach(viewModel.config.groups) { group in
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
                            if !collapsedGroupIDs.contains(group.id) {
                                ForEach(group.nodes) { node in
                                    NodeRow(
                                        name: node.name,
                                        isActive: node.isActive,
                                        isDefault: false,
                                        isSelected: selectedNodeID == node.id
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedNodeID = node.id
                                    }
                                    .onTapGesture(count: 2) {
                                        editingNodeToRename = (group.id, node.id)
                                        renameNodeNewName = node.name
                                        showRenameNodeDialog = true
                                    }
                                    .contextMenu {
                                        Button("删除") {
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
                        moveGroups(from: source, to: destination)
                    }
                }
                .listStyle(.sidebar)
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
            // 右侧：hosts 文本编辑
            if let nodeID = selectedNodeID {
                VStack(alignment: .leading, spacing: 0) {
                    // 工具栏
                    HStack {
                        Text(editingName)
                            .font(.headline)
                            .lineLimit(1)

                        Spacer()

                        Button("应用") {
                            saveCurrentNode()
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.return, modifiers: .command)

                        Button("撤销") {
                            reloadContent(id: nodeID)
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut("z", modifiers: .command)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    Divider()

                    // 文本编辑器
                    TextEditor(text: $editingContent)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(Color(NSColor.textBackgroundColor))
                        .frame(minWidth: 400, minHeight: 300)

                    // 状态栏
                    HStack {
                        if viewModel.isApplying {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在应用...")
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

                        Text("\(editingContent.count) 字符")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                }
            } else {
                ContentUnavailableView("选择一个节点", systemImage: "doc.text")
            }
        }
        .alert("确认删除节点", isPresented: $showDeleteConfirmation) {
            Button("删除", role: .destructive) {
                if let (groupID, nodeID) = nodeToDelete {
                    let service = mutationService
                    service.removeNode(id: nodeID, fromGroup: groupID, in: &viewModel.config)
                    viewModel.scheduleApply()
                }
                nodeToDelete = nil
            }
            Button("取消", role: .cancel) {
                nodeToDelete = nil
            }
        } message: {
            Text("删除后无法恢复，是否继续？")
        }
        .alert("确认删除分组", isPresented: $showDeleteGroupConfirmation) {
            Button("删除", role: .destructive) {
                if let groupID = groupToDelete {
                    let service = mutationService
                    service.removeGroup(id: groupID, from: &viewModel.config)
                    viewModel.scheduleApply()
                }
                groupToDelete = nil
            }
            Button("取消", role: .cancel) {
                groupToDelete = nil
            }
        } message: {
            Text("删除分组将同时删除其下所有节点，是否继续？")
        }
        .frame(minWidth: 700, minHeight: 500)
        .overlay {
            if showAddGroupDialog {
                NameInputDialog(
                    title: "新建分组",
                    placeholder: "分组名称",
                    confirmTitle: "添加",
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
                    title: "新建节点",
                    placeholder: "节点名称",
                    confirmTitle: "添加",
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
                    title: "重命名节点",
                    placeholder: "新名称",
                    confirmTitle: "确认",
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

    private func loadNodeContent(id: UUID?) {
        guard let id = id else {
            editingContent = ""
            editingName = ""
            return
        }

        if id == viewModel.config.defaultNode.id {
            editingContent = viewModel.config.defaultNode.content
            editingName = viewModel.config.defaultNode.name
            return
        }

        for group in viewModel.config.groups {
            if let node = group.nodes.first(where: { $0.id == id }) {
                editingContent = node.content
                editingName = node.name
                return
            }
        }
    }

    /// 撤销时只重置编辑内容，不影响节点名称
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

    private func moveGroups(from source: IndexSet, to destination: Int) {
        viewModel.config.groups.move(fromOffsets: source, toOffset: destination)
        viewModel.scheduleApply()
    }


}

