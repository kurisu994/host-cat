import AppKit
import HostCatCore
import SwiftUI

/// 菜单栏下拉内容视图
struct MenuBarContentView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("HostCat")
            .font(.headline)

        Divider()

        // 默认节点（始终激活，不可切换）
        Toggle(viewModel.defaultNodeItem.name, isOn: .constant(true))
            .disabled(true)

        Divider()

        // 分组和节点，使用 Toggle 映射到 NSMenuItem 原生 checkmark
        ForEach(viewModel.groupItems) { group in
            Text(group.name)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(group.nodes) { node in
                Toggle(
                    node.name,
                    isOn: nodeActiveBinding(nodeID: node.id, groupID: node.groupID)
                )
            }

            Divider()
        }

        // 操作菜单
        Button("查看合成 Hosts") {
            viewModel.updateMergedPreview()
            openAppWindow(id: "preview", title: "合成预览")
        }

        Button("打开编辑器") {
            openAppWindow(id: "editor", title: "编辑器")
        }

        if viewModel.isApplying {
            Text("正在应用...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if let error = viewModel.applyError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }

        Divider()

        Button("退出") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func openAppWindow(id: String, title: String) {
        openWindow(id: id)
        WindowFocus.focusSoon(title: title)
    }

    /// 为指定节点创建 isActive 的双向绑定，Toggle 切换时自动同步 config 并触发应用
    private func nodeActiveBinding(nodeID: UUID, groupID: UUID?) -> Binding<Bool> {
        Binding(
            get: {
                guard let groupID = groupID,
                      let group = viewModel.config.groups.first(where: { $0.id == groupID }),
                      let node = group.nodes.first(where: { $0.id == nodeID }) else {
                    return false
                }
                return node.isActive
            },
            set: { _ in
                viewModel.toggleNode(id: nodeID, inGroup: groupID)
            }
        )
    }
}
