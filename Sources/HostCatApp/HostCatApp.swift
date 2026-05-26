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
        // Development: use PreviewHostHelperClient to bypass Helper registration,
        // avoiding the need to install the Privileged Helper during development.
        let helperClient: any HostHelperClient = PreviewHostHelperClient()
        #else
        let helperClient: any HostHelperClient = XPCHostHelperClient()
        #endif

        let coordinator = HostWriteCoordinator(helperClient: helperClient)
        _viewModel = StateObject(wrappedValue: MenuBarViewModel(config: config, coordinator: coordinator))
    }

    var body: some Scene {
        MenuBarExtra("HostCat", systemImage: "pawprint") {
            MenuBarContentView(viewModel: viewModel)
                .externalModificationAlert(viewModel: viewModel)
        }
        .menuBarExtraStyle(.menu)

        Window(L.editorTitle, id: "editor") {
            EditorView(viewModel: viewModel)
                .externalModificationAlert(viewModel: viewModel)
                .background(WindowFocusView(title: L.editorTitle))
        }
        .defaultSize(width: 900, height: 600)

        Window(L.previewMergedHosts, id: "preview") {
            MergedPreviewView(viewModel: viewModel)
                .externalModificationAlert(viewModel: viewModel)
                .background(WindowFocusView(title: L.previewMergedHosts))
        }
        .defaultSize(width: 700, height: 500)

        Window(L.helperTitle, id: "helper-setup") {
            HelperSetupView(registrationManager: registrationManager)
        }
        .defaultSize(width: 400, height: 350)

        Window(L.backupTitle, id: "backup") {
            BackupRestoreView(viewModel: viewModel)
                .externalModificationAlert(viewModel: viewModel)
        }
        .defaultSize(width: 700, height: 450)

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

// MARK: - Settings View

/// Settings page containing general settings, Helper status, and configuration info.
private struct SettingsView: View {
    let config: AppConfig
    @ObservedObject var registrationManager: HelperRegistrationManager

    var body: some View {
        Form {
            // General settings
            Section(L.settingsGeneral) {
                Toggle(L.settingsLaunchAtLogin, isOn: launchAtLoginBinding)
            }

            // Helper status
            Section(L.settingsHelper) {
                LabeledContent(L.sidebarGroups) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(helperStatusColor)
                            .frame(width: 8, height: 8)
                        Text(registrationManager.helperStatusDescription)
                    }
                }

                if !registrationManager.isHelperReady {
                    if registrationManager.isHelperRequiresApproval {
                        Button(L.helperReinstall) {
                            registrationManager.openSystemSettings()
                        }
                    } else {
                        Button(L.helperInstall) {
                            registrationManager.registerHelper()
                        }
                    }
                }

                Button(L.settingsRefresh) {
                    registrationManager.refreshHelperStatus()
                }

                if let error = registrationManager.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            // Configuration info
            Section(L.settingsConfigInfo) {
                LabeledContent(L.settingsVersion, value: "\(config.configVersion)")
                LabeledContent(L.sidebarDefault, value: config.defaultNode.name)
                LabeledContent(L.sidebarGroups, value: "\(config.groups.count)")
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            registrationManager.refreshHelperStatus()
        }
    }

    /// Launch at login Toggle binding.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { registrationManager.isLaunchAtLoginEnabled },
            set: { registrationManager.setLaunchAtLogin($0) }
        )
    }

    /// Helper status indicator color.
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
