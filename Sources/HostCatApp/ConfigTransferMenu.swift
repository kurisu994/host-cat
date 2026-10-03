import AppKit
import HostCatCore
import SwiftUI
import UniformTypeIdentifiers

/// 编辑器工具栏中的「更多」菜单：导出配置 / 导入配置。
///
/// 导入前先校验版本与格式，再让用户选择「合并」或「替换」；业务逻辑委托给 `MenuBarViewModel`。
struct ConfigTransferMenu: View {
    @ObservedObject var viewModel: MenuBarViewModel
    /// 导入完成后回调，编辑器据此刷新当前选中节点。
    let onImported: () -> Void

    @State private var pendingImport: AppConfig?
    @State private var resultMessage: String?

    var body: some View {
        Menu {
            Button(L.transferExport, systemImage: "square.and.arrow.up") { exportConfig() }
            Button(L.transferImport, systemImage: "square.and.arrow.down") { chooseImportFile() }
        } label: {
            Label(L.transferMenu, systemImage: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L.transferMenu)
        .alert(
            L.transferImportDialogTitle,
            isPresented: Binding(
                get: { pendingImport != nil },
                set: { if !$0 { pendingImport = nil } }
            )
        ) {
            Button(L.transferImportMerge) { performImport(.merge) }
            Button(L.transferImportReplace, role: .destructive) { performImport(.replace) }
            Button(L.dialogCancel, role: .cancel) { pendingImport = nil }
        } message: {
            Text(L.transferImportDialogMessage)
        }
        .alert(
            L.transferResultTitle,
            isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            )
        ) {
            Button(L.dialogOK) { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.title = L.transferExportPanelTitle
        panel.nameFieldStringValue = "HostCat-Config.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try viewModel.exportConfigData().write(to: url, options: .atomic)
            resultMessage = L.transferExportSuccess(url.lastPathComponent)
        } catch {
            resultMessage = L.transferFailed(error.localizedDescription)
        }
    }

    private func chooseImportFile() {
        let panel = NSOpenPanel()
        panel.title = L.transferImportPanelTitle
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            pendingImport = try viewModel.decodeImportedConfig(Data(contentsOf: url))
        } catch {
            resultMessage = L.transferFailed(error.localizedDescription)
        }
    }

    private func performImport(_ mode: ConfigImportMode) {
        guard let imported = pendingImport else { return }
        pendingImport = nil
        let summary = viewModel.importConfig(imported, mode: mode)
        onImported()
        resultMessage = L.transferImportSuccess(
            groups: summary.addedGroups,
            nodes: summary.addedNodes,
            updated: summary.updatedNodes
        )
    }
}
