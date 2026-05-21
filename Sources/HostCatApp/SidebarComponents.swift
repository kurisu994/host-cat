import SwiftUI

/// 节点行视图
struct NodeRow: View {
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

/// 分组头视图（折叠箭头、双击重命名、hover 删除按钮）
struct GroupHeader: View {
    let name: String
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @State private var isRenaming = false
    @State private var renameText: String = ""
    @State private var isHovering = false
    @FocusState private var isTextFieldFocused: Bool

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
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        if !renameText.isEmpty {
                            onRename(renameText)
                        }
                        isRenaming = false
                    }
                    .onExitCommand {
                        isRenaming = false
                    }
            } else {
                Text(name)
                    .font(.headline)
                    .onTapGesture(count: 2) {
                        renameText = name
                        isRenaming = true
                        // 菜单栏应用需要激活窗口才能接收键盘输入
                        DispatchQueue.main.async {
                            let app = NSApplication.shared
                            if app.activationPolicy() != .regular {
                                app.setActivationPolicy(.regular)
                            }
                            app.activate(ignoringOtherApps: true)
                            app.keyWindow?.makeKeyAndOrderFront(nil)
                            isTextFieldFocused = true
                        }
                    }
            }

            Spacer()

            // 删除按钮（hover 且非编辑时显示）
            if isHovering && !isRenaming {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("删除分组")
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

/// 侧边栏底部"新建分组"按钮
struct SidebarAddGroupButton: View {
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

/// 分组内"添加节点"按钮
struct AddNodeButton: View {
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
