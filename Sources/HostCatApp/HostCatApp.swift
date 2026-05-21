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
