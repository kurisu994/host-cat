import AppKit
import HostCatCore
import HostCatHelperClient
import SwiftUI

@main
struct HostCatApplication: App {
    @StateObject private var viewModel: MenuBarViewModel

    init() {
        let config = AppConfig.initial(defaultHosts: Self.defaultHosts)
        let coordinator = HostWriteCoordinator(helperClient: PreviewHostHelperClient())
        _viewModel = StateObject(wrappedValue: MenuBarViewModel(config: config, coordinator: coordinator))
    }

    var body: some Scene {
        MenuBarExtra("HostCat", systemImage: "pawprint") {
            MenuBarContentView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(config: viewModel.config)
        }
    }

    private static let defaultHosts = """
    127.0.0.1 localhost
    255.255.255.255 broadcasthost
    ::1 localhost

    """
}

private struct MenuBarContentView: View {
    @ObservedObject var viewModel: MenuBarViewModel

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
        }

        Button("打开编辑器") {
            // TODO: 打开编辑窗口
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
