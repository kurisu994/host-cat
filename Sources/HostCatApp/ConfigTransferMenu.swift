import AppKit
import HostCatCore
import SwiftUI
import UniformTypeIdentifiers

/// 编辑器工具栏中的「更多」菜单：导出配置 / 导入配置。
///
/// 导入前先校验版本与格式，再让用户选择「合并」或「替换」；业务逻辑委托给 `MenuBarViewModel`。
struct ConfigTransferMenu: View {
    @ObservedObject var viewModel: MenuBarViewModel
    /// 编辑器里是否还有未点「应用」的修改。导出和导入都只看已保存配置。
    let hasUnsavedEdits: Bool
    let onApplyEdits: () -> Void
    let onDiscardEdits: () -> Void
    /// 导入完成后回调，编辑器据此刷新当前选中节点。
    let onImported: () -> Void

    private enum TransferIntent {
        case export
        case importFile
    }

    /// 同一个菜单上只能稳定展示一个 alert，导入确认和结果提示共用这一处。
    private enum TransferPrompt: Identifiable {
        case unsaved(TransferIntent)
        case chooseMode
        case result(String)

        var id: String {
            switch self {
            case .unsaved(let intent):
                switch intent {
                case .export: "unsaved-export"
                case .importFile: "unsaved-import"
                }
            case .chooseMode: "choose-mode"
            case .result: "result"
            }
        }
    }

    @State private var prompt: TransferPrompt?
    @State private var pendingImport: AppConfig?

    var body: some View {
        Menu {
            Button(L.transferExport, systemImage: "square.and.arrow.up") { begin(.export) }
            Button(L.transferImport, systemImage: "square.and.arrow.down") { begin(.importFile) }
        } label: {
            Label(L.transferMenu, systemImage: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L.transferMenu)
        .alert(
            promptTitle,
            isPresented: Binding(
                get: { prompt != nil },
                set: { if !$0 { prompt = nil } }
            ),
            presenting: prompt
        ) { prompt in
            switch prompt {
            case let .unsaved(intent):
                Button(L.transferUnsavedApply) { resolveUnsaved(intent, apply: true) }
                Button(L.transferUnsavedDiscard) { resolveUnsaved(intent, apply: false) }
                Button(L.dialogCancel, role: .cancel) { self.prompt = nil }
            case .chooseMode:
                Button(L.transferImportMerge) { performImport(.merge) }
                Button(L.transferImportReplace, role: .destructive) { performImport(.replace) }
                Button(L.dialogCancel, role: .cancel) {
                    pendingImport = nil
                    self.prompt = nil
                }
            case .result:
                Button(L.dialogOK) { self.prompt = nil }
            }
        } message: { prompt in
            switch prompt {
            case .unsaved:
                Text(L.transferUnsavedMessage)
            case .chooseMode:
                Text(L.transferImportDialogMessage)
            case let .result(message):
                Text(message)
            }
        }
    }

    private var promptTitle: String {
        switch prompt {
        case .unsaved: L.transferUnsavedTitle
        case .chooseMode: L.transferImportDialogTitle
        case .result, .none: L.transferResultTitle
        }
    }

    private func begin(_ intent: TransferIntent) {
        if hasUnsavedEdits {
            prompt = .unsaved(intent)
            return
        }
        continueTransfer(intent)
    }

    private func resolveUnsaved(_ intent: TransferIntent, apply: Bool) {
        if apply {
            onApplyEdits()
        } else {
            onDiscardEdits()
        }
        prompt = nil
        // 等当前 alert 收起后再弹文件面板或下一个 alert，否则第二个提示不会出现。
        DispatchQueue.main.async {
            continueTransfer(intent)
        }
    }

    private func continueTransfer(_ intent: TransferIntent) {
        switch intent {
        case .export:
            exportConfig()
        case .importFile:
            chooseImportFile()
        }
    }

    private func showResult(_ message: String) {
        DispatchQueue.main.async {
            prompt = .result(message)
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
            showResult(L.transferExportSuccess(url.lastPathComponent))
        } catch {
            showResult(L.transferFailed(error.localizedDescription))
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
            prompt = .chooseMode
        } catch {
            pendingImport = nil
            showResult(L.transferFailed(error.localizedDescription))
        }
    }

    private func performImport(_ mode: ConfigImportMode) {
        guard let imported = pendingImport else { return }
        pendingImport = nil
        prompt = nil
        let summary = viewModel.importConfig(imported, mode: mode)
        onImported()
        let message: String
        if mode == .replace {
            message = L.transferReplaceSuccess(groups: summary.addedGroups, nodes: summary.addedNodes)
        } else {
            message = L.transferImportSuccess(
                groups: summary.addedGroups,
                nodes: summary.addedNodes,
                updated: summary.updatedNodes
            )
        }
        showResult(message)
    }
}
