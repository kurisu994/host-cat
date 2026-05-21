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
                            isSingleSelect: group.isSingleSelect,
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
                            onToggleSingleSelect: {
                                let service = mutationService
                                service.setGroupSingleSelect(!group.isSingleSelect, forGroup: group.id, in: &viewModel.config)
                                viewModel.scheduleApply()
                            },
                            onDelete: {
                                let service = mutationService
                                service.removeGroup(id: group.id, from: &viewModel.config)
                                viewModel.scheduleApply()
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

// MARK: - Subviews

private struct NodeRow: View {
    let name: String
    let isActive: Bool
    let isDefault: Bool
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? .green : .secondary)
            Text(name)

            Spacer()

            if isDefault {
                Text("默认")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
            }
        }
    }
}

private struct GroupHeader: View {
    let name: String
    let isSingleSelect: Bool
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void
    let onRename: (String) -> Void
    let onToggleSingleSelect: () -> Void
    let onDelete: () -> Void

    @State private var isRenaming = false
    @State private var renameText: String = ""

    var body: some View {
        HStack {
            // 折叠箭头
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                .animation(.easeInOut(duration: 0.2), value: isCollapsed)
                .onTapGesture {
                    onToggleCollapse()
                }

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
                Button("删除分组", role: .destructive) {
                    onDelete()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

private struct SidebarAddGroupButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))

                Text("新建分组")
                    .font(.system(size: 13))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovering ? .primary : .secondary)
        .background(Color(NSColor.controlBackgroundColor))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .help("新建分组")
    }
}

private struct AddNodeButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                Text("添加节点")
                    .font(.system(size: 12))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.secondary.opacity(isHovering ? 0.5 : 0.25))
            )
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(isHovering ? 0.06 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .help("在此分组中添加新节点")
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

        // 输入法正在组合（如拼音输入中），不要强制同步 stringValue，否则会打断 IME
        let hasMarkedText = (textField.currentEditor() as? NSTextView)?.hasMarkedText() ?? false
        if !hasMarkedText, textField.stringValue != text {
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
            // 输入法正在组合字符时（如中文拼音），跳过更新 binding，
            // 避免触发 SwiftUI 重建导致 updateNSView 打断 IME 状态
            if let editor = textField.currentEditor() as? NSTextView, editor.hasMarkedText() {
                return
            }
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
                // 菜单栏应用延迟稍长，多试几次
                for delay in [0, 10, 50, 100, 200, 400] {
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

            // 菜单栏应用默认 activation policy 是 .accessory，
            // 必须临时切到 .regular 才能可靠获取键盘焦点
            let app = NSApplication.shared
            if app.activationPolicy() != .regular {
                app.setActivationPolicy(.regular)
            }
            app.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            window.makeFirstResponder(textField)
            textField.selectText(nil)
            return textField.currentEditor() != nil
        }
    }
}

// MARK: - Node Reorder Drop Delegate

private struct NodeReorderDropDelegate: DropDelegate {
    let targetNodeID: UUID
    let groupID: UUID
    @Binding var draggingNodeID: UUID?
    let viewModel: MenuBarViewModel

    func dropEntered(info: DropInfo) {
        guard let draggingID = draggingNodeID,
              draggingID != targetNodeID,
              let groupIndex = viewModel.config.groups.firstIndex(where: { $0.id == groupID }),
              let fromIndex = viewModel.config.groups[groupIndex].nodes.firstIndex(where: { $0.id == draggingID }),
              let toIndex = viewModel.config.groups[groupIndex].nodes.firstIndex(where: { $0.id == targetNodeID })
        else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.config.groups[groupIndex].nodes.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingNodeID = nil
        viewModel.scheduleApply()
        return true
    }

    func dropExited(info: DropInfo) {
        // 拖出范围时不清除，等 performDrop 处理
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggingNodeID != nil
    }
}
