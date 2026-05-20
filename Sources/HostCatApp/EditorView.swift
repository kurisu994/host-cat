import HostCatCore
import SwiftUI

struct EditorView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @State private var selectedNodeID: UUID?
    @State private var editingContent: String = ""
    @State private var editingName: String = ""
    @State private var showDeleteConfirmation = false
    @State private var nodeToDelete: (groupID: UUID, nodeID: UUID)?
    @State private var showAddGroupSheet = false
    @State private var newGroupName: String = ""
    @State private var showAddNodeSheet = false
    @State private var newNodeName: String = ""
    @State private var selectedGroupForNewNode: UUID?

    var body: some View {
        NavigationSplitView {
            // 左侧：分组和节点树
            List(selection: $selectedNodeID) {
                // 默认节点
                Section("默认") {
                    NodeRow(
                        name: viewModel.config.defaultNode.name,
                        isActive: viewModel.config.defaultNode.isActive,
                        isDefault: true
                    )
                    .tag(viewModel.config.defaultNode.id)
                }

                // 分组
                ForEach(viewModel.config.groups) { group in
                    Section(header: GroupHeader(
                        name: group.name,
                        isSingleSelect: group.isSingleSelect,
                        onRename: { newName in
                            var service = ConfigMutationService()
                            service.renameGroup(id: group.id, to: newName, in: &viewModel.config)
                            viewModel.scheduleApply()
                        },
                        onToggleSingleSelect: {
                            var service = ConfigMutationService()
                            service.setGroupSingleSelect(!group.isSingleSelect, forGroup: group.id, in: &viewModel.config)
                            viewModel.scheduleApply()
                        },
                        onDelete: {
                            var service = ConfigMutationService()
                            service.removeGroup(id: group.id, from: &viewModel.config)
                            viewModel.scheduleApply()
                        },
                        onMoveUp: {
                            var service = ConfigMutationService()
                            service.moveGroup(id: group.id, direction: .up, in: &viewModel.config)
                            viewModel.scheduleApply()
                        },
                        onMoveDown: {
                            var service = ConfigMutationService()
                            service.moveGroup(id: group.id, direction: .down, in: &viewModel.config)
                            viewModel.scheduleApply()
                        }
                    )) {
                        ForEach(group.nodes) { node in
                            NodeRow(
                                name: node.name,
                                isActive: node.isActive,
                                isDefault: false
                            )
                            .tag(node.id)
                            .contextMenu {
                                Button("重命名") {
                                    // TODO: 显示重命名对话框
                                }
                                Button("删除") {
                                    nodeToDelete = (group.id, node.id)
                                    showDeleteConfirmation = true
                                }
                                Divider()
                                Button("上移") {
                                    var service = ConfigMutationService()
                                    service.moveNode(id: node.id, direction: .up, inGroup: group.id, in: &viewModel.config)
                                    viewModel.scheduleApply()
                                }
                                Button("下移") {
                                    var service = ConfigMutationService()
                                    service.moveNode(id: node.id, direction: .down, inGroup: group.id, in: &viewModel.config)
                                    viewModel.scheduleApply()
                                }
                            }
                        }

                        Button("添加节点") {
                            selectedGroupForNewNode = group.id
                            showAddNodeSheet = true
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200)
            .toolbar {
                ToolbarItem {
                    Button("添加分组") {
                        showAddGroupSheet = true
                    }
                }
            }
            .onChange(of: selectedNodeID) { _, newID in
                loadNodeContent(id: newID)
            }
        } detail: {
            // 右侧：hosts 文本编辑
            if let nodeID = selectedNodeID {
                VStack(spacing: 0) {
                    // 工具栏
                    HStack {
                        TextField("节点名称", text: $editingName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)

                        Spacer()

                        Button("应用") {
                            saveCurrentNode()
                        }
                        .keyboardShortcut(.return, modifiers: .command)

                        Button("撤销") {
                            loadNodeContent(id: nodeID)
                        }
                        .keyboardShortcut("z", modifiers: .command)
                    }
                    .padding()

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
        .sheet(isPresented: $showAddGroupSheet) {
            AddGroupSheet(name: $newGroupName) {
                guard !newGroupName.isEmpty else { return }
                var service = ConfigMutationService()
                service.addGroup(named: newGroupName, to: &viewModel.config)
                viewModel.scheduleApply()
                newGroupName = ""
                showAddGroupSheet = false
            }
        }
        .sheet(isPresented: $showAddNodeSheet) {
            AddNodeSheet(name: $newNodeName) {
                guard !newNodeName.isEmpty, let groupID = selectedGroupForNewNode else { return }
                var service = ConfigMutationService()
                service.addNode(named: newNodeName, content: "", toGroup: groupID, in: &viewModel.config)
                viewModel.scheduleApply()
                newNodeName = ""
                showAddNodeSheet = false
            }
        }
        .alert("确认删除", isPresented: $showDeleteConfirmation) {
            Button("删除", role: .destructive) {
                if let (groupID, nodeID) = nodeToDelete {
                    var service = ConfigMutationService()
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
        .frame(minWidth: 700, minHeight: 500)
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

    private func saveCurrentNode() {
        guard let id = selectedNodeID else { return }
        var service = ConfigMutationService()

        if id == viewModel.config.defaultNode.id {
            service.updateDefaultNodeContent(editingContent, in: &viewModel.config)
            service.renameDefaultNode(to: editingName, in: &viewModel.config)
        } else {
            for group in viewModel.config.groups {
                if group.nodes.contains(where: { $0.id == id }) {
                    service.updateNodeContent(id: id, content: editingContent, inGroup: group.id, in: &viewModel.config)
                    service.renameNode(id: id, to: editingName, inGroup: group.id, in: &viewModel.config)
                    break
                }
            }
        }

        viewModel.scheduleApply()
    }
}

// MARK: - Subviews

private struct NodeRow: View {
    let name: String
    let isActive: Bool
    let isDefault: Bool

    var body: some View {
        HStack {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? .green : .secondary)
            Text(name)
            if isDefault {
                Text("默认")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(3)
            }
        }
    }
}

private struct GroupHeader: View {
    let name: String
    let isSingleSelect: Bool
    let onRename: (String) -> Void
    let onToggleSingleSelect: () -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    @State private var isRenaming = false
    @State private var renameText: String = ""

    var body: some View {
        HStack {
            if isRenaming {
                TextField("分组名称", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        onRename(renameText)
                        isRenaming = false
                    }
            } else {
                Text(name)
                    .font(.headline)
                Image(systemName: isSingleSelect ? "1.circle" : "infinity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(isSingleSelect ? "单选组" : "多选组")
            }

            Spacer()

            Menu {
                Button("重命名") {
                    renameText = name
                    isRenaming = true
                }
                Button(isSingleSelect ? "切换为多选" : "切换为单选") {
                    onToggleSingleSelect()
                }
                Divider()
                Button("上移") { onMoveUp() }
                Button("下移") { onMoveDown() }
                Divider()
                Button("删除分组", role: .destructive) {
                    onDelete()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AddGroupSheet: View {
    @Binding var name: String
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("新建分组")
                .font(.headline)

            TextField("分组名称", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("取消", role: .cancel) {}
                Button("添加") {
                    onAdd()
                }
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

private struct AddNodeSheet: View {
    @Binding var name: String
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("新建节点")
                .font(.headline)

            TextField("节点名称", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("取消", role: .cancel) {}
                Button("添加") {
                    onAdd()
                }
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }
}
