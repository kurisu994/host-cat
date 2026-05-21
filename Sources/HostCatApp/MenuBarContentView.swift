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
        Button {
            // 默认节点不可停用
        } label: {
            HStack {
                Image(systemName: "checkmark")
                    .opacity(viewModel.defaultNodeItem.isActive ? 1 : 0)
                Text(viewModel.defaultNodeItem.name)
            }
        }
        .disabled(true)

        Divider()

        // 分组和节点
        ForEach(viewModel.groupItems) { group in
            Text(group.name)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(group.nodes) { node in
                Button {
                    viewModel.toggleNode(id: node.id, inGroup: node.groupID)
                } label: {
                    HStack {
                        Image(systemName: "checkmark")
                            .opacity(node.isActive ? 1 : 0)
                        Text(node.name)
                    }
                }
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
}
