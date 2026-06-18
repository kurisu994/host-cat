import AppKit
import HostCatCore
import SwiftUI

/// Menu bar dropdown content view.
struct MenuBarContentView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @Environment(\.openWindow) private var openWindow
    @StateObject private var hoverPreviewPanelController = HoverPreviewPanelController()
    @AppStorage(AppLanguage.preferenceKey) private var storedLanguage = AppLanguage.system.rawValue

    var body: some View {
        menuItems
            .id(storedLanguage)
    }

    /// `.menu` 样式会复用原生菜单项，语言改变时以新 identity 重建文本内容。
    @ViewBuilder
    private var menuItems: some View {
        Text("HostCat")
            .font(.headline)

        #if DEBUG
        // Debug 构建用 PreviewHostHelperClient，菜单里加一条 disabled 项明示，
        // 避免开发者从菜单切换节点后误以为已落盘 /etc/hosts。
        Label("⚠️ DEBUG：写入未真正落盘到 /etc/hosts", systemImage: "exclamationmark.triangle.fill")
        #endif

        Divider()

        // Default node (always active, cannot be toggled)
        Toggle(viewModel.defaultNodeItem.name, isOn: .constant(true))
            .disabled(true)

        Divider()

        // Groups and nodes, using Toggle mapped to native NSMenuItem checkmark.
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

        // Actions menu
         Button(L.editorTitle) {
            openAppWindow(id: "editor", title: L.editorTitle)
        }
        
        Button(L.previewTitle) {
            viewModel.updateMergedPreview()
            openAppWindow(id: "preview", title: L.previewMergedHosts)
        }
        .onHover { hovering in
            if hovering {
                viewModel.updateMergedPreview()
                hoverPreviewPanelController.show(text: viewModel.lastMergedText ?? L.previewNoContent)
            } else {
                hoverPreviewPanelController.hide()
            }
        }
        .onDisappear {
            hoverPreviewPanelController.hide()
        }

        Divider()

        Button(L.backupTitle) {
            openAppWindow(id: "backup", title: L.backupTitle)
        }

        SettingsLink {
            Text(L.settingsTitle)
        }

        if viewModel.isApplying {
            Label(L.editorApplying, systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if let error = viewModel.applyError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        }

        Divider()

        Button(L.quit) {
            NSApplication.shared.terminate(nil)
        }
    }

    private func openAppWindow(id: String, title: String) {
        openWindow(id: id)
        WindowFocus.focusSoon(title: title)
    }

    /// Creates a two-way binding for a node's isActive state; Toggle changes automatically sync config and trigger apply.
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
