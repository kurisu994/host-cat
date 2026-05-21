import AppKit
import HostCatCore
import SwiftUI

struct EditorView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @State private var selectedNodeID: UUID?
    @State private var editingContent: String = ""
    @State private var editingName: String = ""
    @State private var showDeleteConfirmation = false
    @State private var nodeToDelete: (groupID: UUID, nodeID: UUID)?
    @State private var showAddGroupDialog = false
    @State private var newGroupName: String = ""
    @State private var showAddNodeDialog = false
    @State private var newNodeName: String = ""
    @State private var selectedGroupForNewNode: UUID?
    @State private var showRenameNodeDialog = false
    @State private var editingNodeToRename: (groupID: UUID, nodeID: UUID)?
    @State private var renameNodeNewName: String = ""
    @State private var mutationService = ConfigMutationService()

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
                            let service = mutationService
                            service.renameGroup(id: group.id, to: newName, in: &viewModel.config)
                            viewModel.scheduleApply()
                        },
                        onToggleSingleSelect: {
                            let service = mutationService
                            service.setGroupSingleSelect(!group.isSingleSelect, forGroup: group.id, in: &viewModel.config)
                            viewModel.scheduleApply()
                        },
                        onDelete: {
                            let service = mutationService
                            service.removeGroup(id: group.id, from: &viewModel.config)
                            viewModel.scheduleApply()
                        },
                        onMoveUp: {
                            let service = mutationService
                            service.moveGroup(id: group.id, direction: .up, in: &viewModel.config)
                            viewModel.scheduleApply()
                        },
                        onMoveDown: {
                            let service = mutationService
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
                                    editingNodeToRename = (group.id, node.id)
                                    renameNodeNewName = node.name
                                    showRenameNodeDialog = true
                                }
                                Button("删除") {
                                    nodeToDelete = (group.id, node.id)
                                    showDeleteConfirmation = true
                                }
                                Divider()
                                Button("上移") {
                                    let service = mutationService
                                    service.moveNode(id: node.id, direction: .up, inGroup: group.id, in: &viewModel.config)
                                    viewModel.scheduleApply()
                                }
                                Button("下移") {
                                    let service = mutationService
                                    service.moveNode(id: node.id, direction: .down, inGroup: group.id, in: &viewModel.config)
                                    viewModel.scheduleApply()
                                }
                            }
                        }

                        Button("添加节点") {
                            selectedGroupForNewNode = group.id
                            newNodeName = ""
                            showAddNodeDialog = true
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
                        newGroupName = ""
                        showAddGroupDialog = true
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
        .alert("确认删除", isPresented: $showDeleteConfirmation) {
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

    private func saveCurrentNode() {
        guard let id = selectedNodeID else { return }
        let service = mutationService

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

private struct NameInputDialog: View {
    let title: String
    let placeholder: String
    let confirmTitle: String
    @Binding var name: String
    let onCancel: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text(title)
                    .font(.headline)

                FocusedNameTextField(
                    placeholder: placeholder,
                    text: $name,
                    onSubmit: submit
                )
                .frame(height: 24)

                HStack {
                    Button("取消", role: .cancel) {
                        onCancel()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button(confirmTitle) {
                        submit()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
                }
            }
            .padding(24)
            .frame(width: 360)
            .background(Color(NSColor.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
        }
    }

    private var canSubmit: Bool {
        !name.isEmpty
    }

    @MainActor
    private func submit() {
        guard canSubmit else { return }
        onSubmit()
    }
}

private struct FocusedNameTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.stringValue = text
        textField.bezelStyle = .roundedBezel
        textField.isEditable = true
        textField.isSelectable = true
        textField.delegate = context.coordinator
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.submit(_:))
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit

        if textField.placeholderString != placeholder {
            textField.placeholderString = placeholder
        }

        if textField.stringValue != text {
            textField.stringValue = text
        }

        context.coordinator.focus(textField)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        private var didRequestFocus = false

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text.wrappedValue = textField.stringValue
        }

        @objc func submit(_ sender: NSTextField) {
            text.wrappedValue = sender.stringValue
            onSubmit()
        }

        func focus(_ textField: NSTextField) {
            guard !didRequestFocus else { return }
            didRequestFocus = true

            Task { @MainActor in
                for delay in [0, 10, 50, 100, 200] {
                    if delay > 0 {
                        try? await Task.sleep(for: .milliseconds(delay))
                    }
                    if focusNow(textField) {
                        return
                    }
                }
            }
        }

        private func focusNow(_ textField: NSTextField) -> Bool {
            guard let window = textField.window else { return false }
            guard textField.currentEditor() == nil else { return true }
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(textField)
            textField.selectText(nil)
            return textField.currentEditor() != nil
        }
    }
}
