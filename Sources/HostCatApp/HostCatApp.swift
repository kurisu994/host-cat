import AppKit
import HostCatCore
import HostCatHelperClient
import SwiftUI

@main
struct HostCatApplication: App {
    @StateObject private var viewModel: MenuBarViewModel

    init() {
        let config = Self.loadInitialConfig()
        let coordinator = HostWriteCoordinator(helperClient: PreviewHostHelperClient())
        _viewModel = StateObject(wrappedValue: MenuBarViewModel(config: config, coordinator: coordinator))
    }

    var body: some Scene {
        MenuBarExtra("HostCat", systemImage: "pawprint") {
            MenuBarContentView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.menu)

        Window("编辑器", id: "editor") {
            EditorView(viewModel: viewModel)
                .background(WindowFocusView(title: "编辑器"))
        }
        .defaultSize(width: 900, height: 600)

        Window("合成预览", id: "preview") {
            MergedPreviewView(viewModel: viewModel)
                .background(WindowFocusView(title: "合成预览"))
        }
        .defaultSize(width: 700, height: 500)

        Settings {
            SettingsView(config: viewModel.config)
        }
    }

    private static let defaultHosts = """
    127.0.0.1 localhost
    255.255.255.255 broadcasthost
    ::1 localhost

    """

    private static func loadInitialConfig() -> AppConfig {
        let importedHosts = readImportedDefaultHosts()
        let store = AppConfigStore()

        do {
            return try store.load(defaultHosts: importedHosts).config
        } catch {
            return AppConfig.initial(defaultHosts: importedHosts)
        }
    }

    private static func readImportedDefaultHosts() -> String {
        let hostsURL = URL(fileURLWithPath: "/etc/hosts")
        guard let data = try? Data(contentsOf: hostsURL) else {
            return defaultHosts
        }

        return HostsImporter().importHostsWithFallback(data: data).defaultNodeContent
    }
}

private struct MenuBarContentView: View {
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

private struct WindowFocusView: NSViewRepresentable {
    let title: String

    func makeNSView(context _: Context) -> NSView {
        FocusHostingView(title: title)
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        guard let view = nsView as? FocusHostingView else { return }
        view.title = title
    }

    private final class FocusHostingView: NSView {
        var title: String

        init(title: String) {
            self.title = title
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            focusWindowIfAvailable()
        }

        func focusWindowIfAvailable() {
            guard let window else { return }
            WindowFocus.focusOnce(window: window)
        }
    }
}

@MainActor
private enum WindowFocus {
    private static var focusedWindowIDs: Set<ObjectIdentifier> = []

    static func focusSoon(title: String) {
        focus(title: title)
        Task { @MainActor in
            focus(title: title)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            focus(title: title)
        }
    }

    static func focus(title: String) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard let window = NSApplication.shared.windows.first(where: { $0.title == title }) else { return }
        focus(window: window)
    }

    static func focusOnce(window: NSWindow) {
        let windowID = ObjectIdentifier(window)
        guard focusedWindowIDs.insert(windowID).inserted else { return }
        focus(window: window)
    }

    static func focus(window: NSWindow) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

private struct SettingsView: View {
    let config: AppConfig

    var body: some View {
        Form {
            LabeledContent("配置版本", value: "\(config.configVersion)")
            LabeledContent("默认节点", value: config.defaultNode.name)
            LabeledContent("分组数量", value: "\(config.groups.count)")
        }
        .padding(24)
        .frame(width: 420)
    }
}
