import AppKit
import HostCatCore
import HostCatHelperClient
import SwiftUI

@main
struct HostCatApplication: App {
    @StateObject private var viewModel: MenuBarViewModel
    @StateObject private var registrationManager = HelperRegistrationManager()

    init() {
        let config = Self.loadInitialConfig()

        #if DEBUG
        // 开发环境：可以用 PreviewHostHelperClient 绕过 Helper 注册
        let helperClient: any HostHelperClient = {
            // 如果 Helper 可用就用真实 client，否则回退到 Preview
            let xpc = XPCHostHelperClient()
            return xpc
        }()
        #else
        let helperClient: any HostHelperClient = XPCHostHelperClient()
        #endif

        let coordinator = HostWriteCoordinator(helperClient: helperClient)
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
            SettingsView(
                config: viewModel.config,
                registrationManager: registrationManager
            )
        }
    }

    private static let defaultHosts = """
    127.0.0.1 localhost
    255.255.255.255 broadcasthost
    ::1 localhost

    """

    private static func loadInitialConfig() -> AppConfig {
        let importResult = readImportedDefaultHosts()
        let store = AppConfigStore()

        do {
            return try store.load(
                defaultHosts: importResult.safeDefaultNodeContent,
                currentHostsHash: importResult.currentHostsHash
            ).config
        } catch {
            return AppConfig.initial(
                defaultHosts: importResult.safeDefaultNodeContent,
                currentHostsHash: importResult.currentHostsHash
            )
        }
    }

    private static func readImportedDefaultHosts() -> HostsImportResult {
        let importer = HostsImporter()
        let hostsURL = URL(fileURLWithPath: "/etc/hosts")
        guard let data = try? Data(contentsOf: hostsURL) else {
            return importer.importHosts(defaultHosts)
        }

        return importer.importHostsWithFallback(data: data)
    }
}

// MARK: - 设置页面

/// 设置页面，包含通用设置、Helper 状态和配置信息
private struct SettingsView: View {
    let config: AppConfig
    @ObservedObject var registrationManager: HelperRegistrationManager

    var body: some View {
        Form {
            // 通用设置
            Section("通用") {
                Toggle("开机自启动", isOn: launchAtLoginBinding)
            }

            // Helper 状态
            Section("Privileged Helper") {
                LabeledContent("状态") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(helperStatusColor)
                            .frame(width: 8, height: 8)
                        Text(registrationManager.helperStatusDescription)
                    }
                }

                if !registrationManager.isHelperReady {
                    if registrationManager.isHelperRequiresApproval {
                        Button("打开系统设置审批") {
                            registrationManager.openSystemSettings()
                        }
                    } else {
                        Button("注册 Helper") {
                            registrationManager.registerHelper()
                        }
                    }
                }

                Button("刷新状态") {
                    registrationManager.refreshHelperStatus()
                }

                if let error = registrationManager.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            // 配置信息
            Section("信息") {
                LabeledContent("配置版本", value: "\(config.configVersion)")
                LabeledContent("默认节点", value: config.defaultNode.name)
                LabeledContent("分组数量", value: "\(config.groups.count)")
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            registrationManager.refreshHelperStatus()
        }
    }

    /// 开机自启动 Toggle binding
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { registrationManager.isLaunchAtLoginEnabled },
            set: { registrationManager.setLaunchAtLogin($0) }
        )
    }

    /// Helper 状态指示灯颜色
    private var helperStatusColor: Color {
        switch registrationManager.helperStatus {
        case .enabled:
            .green
        case .requiresApproval:
            .yellow
        default:
            .red
        }
    }
}

