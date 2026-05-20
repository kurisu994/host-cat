import AppKit
import HostCatCore
import HostCatHelperClient
import SwiftUI

@main
struct HostCatApplication: App {
    @State private var config = AppConfig.initial(defaultHosts: Self.defaultHosts)
    private let helperClient = PreviewHostHelperClient()

    var body: some Scene {
        MenuBarExtra("HostCat", systemImage: "pawprint") {
            Text("HostCat")
                .font(.headline)

            Divider()

            Button("查看合成 Hosts") {
                _ = try? HostsMerger().merge(config)
            }

            Button("应用当前配置") {
                Task {
                    guard let merged = try? HostsMerger().merge(config) else {
                        return
                    }

                    _ = try? await helperClient.writeHosts(
                        merged.text,
                        expectedCurrentHostsHash: config.state.lastAppliedHostsHash
                    )
                }
            }

            Divider()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(config: config)
        }
    }

    private static let defaultHosts = """
    127.0.0.1 localhost
    255.255.255.255 broadcasthost
    ::1 localhost

    """
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
