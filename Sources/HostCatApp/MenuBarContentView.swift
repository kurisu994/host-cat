import AppKit
import HostCatCore
import SwiftUI

/// Menu bar dropdown content view.
struct MenuBarContentView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @Environment(\.openWindow) private var openWindow
    @StateObject private var hoverPreviewPanelController = HoverPreviewPanelController()

    var body: some View {
        Text("HostCat")
            .font(.headline)

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
                hoverPreviewPanelController.show(text: viewModel.lastMergedText ?? L.previewNoConflicts)
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

        Button(L.helperTitle) {
            openAppWindow(id: "helper-setup", title: L.helperTitle)
        }

        if viewModel.isApplying {
            Label(L.editorParsing, systemImage: "arrow.triangle.2.circlepath")
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
