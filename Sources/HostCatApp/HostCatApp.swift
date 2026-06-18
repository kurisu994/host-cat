import AppKit
import HostCatCore
import HostCatHelperClient
import KeyboardShortcuts
import SwiftUI

@main
struct HostCatApplication: App {
    @NSApplicationDelegateAdaptor(HostCatAppDelegate.self) private var appDelegate
    @StateObject private var viewModel: MenuBarViewModel
    @StateObject private var registrationManager = HelperRegistrationManager()
    @AppStorage(AppLanguage.preferenceKey) private var storedLanguage = AppLanguage.system.rawValue

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
                .helperRecoveryAlert(viewModel: viewModel, registrationManager: registrationManager)
                .environment(\.locale, appLanguage.locale)
        }
        .menuBarExtraStyle(.menu)

        Window(L.editorTitle, id: "editor") {
            EditorView(viewModel: viewModel)
                .externalModificationAlert(viewModel: viewModel)
                .helperRecoveryAlert(viewModel: viewModel, registrationManager: registrationManager)
                .debugPreviewBanner()
                .background(WindowFocusView(title: L.editorTitle))
                .environment(\.locale, appLanguage.locale)
        }
        .defaultSize(width: 900, height: 600)

        Window(L.previewMergedHosts, id: "preview") {
            MergedPreviewView(viewModel: viewModel)
                .externalModificationAlert(viewModel: viewModel)
                .helperRecoveryAlert(viewModel: viewModel, registrationManager: registrationManager)
                .debugPreviewBanner()
                .background(WindowFocusView(title: L.previewMergedHosts))
                .environment(\.locale, appLanguage.locale)
        }
        .defaultSize(width: 700, height: 500)

        Window(L.backupTitle, id: "backup") {
            BackupRestoreView(viewModel: viewModel)
                .externalModificationAlert(viewModel: viewModel)
                .helperRecoveryAlert(viewModel: viewModel, registrationManager: registrationManager)
                .debugPreviewBanner()
                .environment(\.locale, appLanguage.locale)
        }
        .defaultSize(width: 700, height: 450)

        Settings {
            SettingsView(
                config: viewModel.config,
                registrationManager: registrationManager,
                preferredLanguage: appLanguageBinding
            )
            .environment(\.locale, appLanguage.locale)
        }
    }

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: storedLanguage) ?? .system
    }

    private var appLanguageBinding: Binding<AppLanguage> {
        Binding(
            get: { appLanguage },
            set: { storedLanguage = $0.rawValue }
        )
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

// MARK: - App Delegate

/// 用于在应用启动完成时挂载全局快捷键监听、首次启动隐私摘要等只需执行一次的副作用。
final class HostCatAppDelegate: NSObject, NSApplicationDelegate {
    /// UserDefaults 中标记隐私摘要是否已展示过的键。
    static let privacyWelcomeShownKey = "HostCat.privacyWelcomeShown"

    private var welcomeWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        GlobalShortcutManager.registerHandlers()
        presentPrivacyWelcomeIfNeeded()
    }

    /// 首次启动时弹出隐私 & 使用方式摘要；用户关闭后写入 UserDefaults 标记，后续启动不再展示。
    @MainActor
    func presentPrivacyWelcomeIfNeeded(userDefaults: UserDefaults = .standard) {
        guard !userDefaults.bool(forKey: Self.privacyWelcomeShownKey) else { return }
        guard welcomeWindowController == nil else { return }

        let language = AppLanguage.stored(in: userDefaults)
        let welcome = WelcomeView { [weak self] in
            self?.welcomeWindowController?.close()
        }
        .environment(\.locale, language.locale)

        let hosting = NSHostingController(rootView: welcome)
        let window = NSWindow(contentViewController: hosting)
        window.title = L.welcomeTitle
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self

        let controller = NSWindowController(window: window)
        welcomeWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension HostCatAppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow,
              closing === welcomeWindowController?.window else {
            return
        }
        UserDefaults.standard.set(true, forKey: Self.privacyWelcomeShownKey)
        welcomeWindowController = nil
    }
}

// MARK: - Settings View

/// 汇总通用设置、Helper 状态和配置信息的设置页面。
private struct SettingsView: View {
    let config: AppConfig
    @ObservedObject var registrationManager: HelperRegistrationManager
    @Binding var preferredLanguage: AppLanguage
    @State private var diagnosticExportStatus: DiagnosticExportStatus?
    @State private var isExportingDiagnostics = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                settingsCard(L.settingsGeneral) {
                    settingsRow {
                        Text(L.settingsLanguage)

                        Spacer()

                        Picker(L.settingsLanguage, selection: $preferredLanguage) {
                            Text(L.languageSystem).tag(AppLanguage.system)
                            Text(L.languageSimplifiedChinese).tag(AppLanguage.simplifiedChinese)
                            Text(L.languageEnglish).tag(AppLanguage.english)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(minWidth: 124)
                    }

                    Divider()
                        .padding(.leading, 14)

                    settingsRow {
                        Text(L.settingsLaunchAtLogin)

                        Spacer()

                        Toggle(L.settingsLaunchAtLogin, isOn: launchAtLoginBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                settingsCard(L.settingsShortcuts) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L.settingsShortcutsDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 10) {
                            Text(L.settingsShortcutToggleMenuBar)

                            Spacer()

                            KeyboardShortcuts.Recorder(for: .toggleMenuBar)
                        }

                        Text(L.settingsShortcutToggleMenuBarHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }

                settingsCard(L.settingsHelper) {
                    settingsRow {
                        Text(L.settingsHelperStatus)

                        Spacer()

                        HStack(spacing: 8) {
                            Circle()
                                .fill(helperStatusColor)
                                .frame(width: 10, height: 10)
                            Text(registrationManager.helperStatusDescription)
                        }
                    }

                    HStack(spacing: 8) {
                        Spacer()

                        if !registrationManager.isHelperReady {
                            if registrationManager.isHelperRequiresApproval {
                                Button(L.helperOpenSettings) {
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
                    }
                    .padding(.top, 6)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)

                    if let error = registrationManager.lastError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                    }
                }

                settingsCard(L.settingsDiagnostics) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L.settingsDiagnosticsDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            Spacer()

                            Button {
                                exportDiagnosticLogs()
                            } label: {
                                if isExportingDiagnostics {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text(L.settingsExportingDiagnostics)
                                    }
                                } else {
                                    Label(
                                        L.settingsExportDiagnosticLogs,
                                        systemImage: "square.and.arrow.up"
                                    )
                                }
                            }
                            .disabled(isExportingDiagnostics)
                        }

                        if let diagnosticExportStatus {
                            Text(diagnosticExportMessage(for: diagnosticExportStatus))
                                .font(.caption)
                                .foregroundStyle(diagnosticExportStatus.isSuccess ? Color.secondary : Color.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }

                settingsCard(L.settingsConfigInfo) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(L.settingsVersion): \(Self.appVersionString)")
                        Text("\(L.settingsConfigVersion): \(config.configVersion)")
                        Text("\(L.settingsDefaultNode): \(config.defaultNode.name)")
                        Text("\(L.settingsGroupCount): \(config.groups.count)")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
        .frame(width: 420)
        .frame(minHeight: 540)
        .onAppear {
            registrationManager.refreshHelperStatus()
        }
    }

    /// 使用接近系统设置窗口的圆角面板样式承载各设置分组。
    private func settingsCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
            }
        }
    }

    /// 统一设置项行的水平留白和高度。
    private func settingsRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            content()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 42)
    }

    /// 启动项开关绑定。
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { registrationManager.isLaunchAtLoginEnabled },
            set: { registrationManager.setLaunchAtLogin($0) }
        )
    }

    /// Helper 状态指示色。
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

    /// 从 Info.plist 读取版本信息，格式为「1.0.0 (build 1 · abc1234)」。
    static var appVersionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let commit = info["HostCatBuildCommit"] as? String ?? "dev"
        return "\(version) (build \(build) · \(commit))"
    }

    /// 打开保存面板并导出最近一小时 HostCat 相关 OSLog。
    private func exportDiagnosticLogs() {
        let panel = NSSavePanel()
        panel.title = L.settingsExportDiagnosticLogs
        panel.nameFieldStringValue = "HostCat-Diagnostics-\(Self.diagnosticFilenameTimestamp()).log"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        isExportingDiagnostics = true
        diagnosticExportStatus = nil
        let exporter = DiagnosticLogExporter()

        Task {
            let result = await Task.detached(priority: .utility) {
                Result {
                    try exporter.export(to: destinationURL)
                }
            }.value

            isExportingDiagnostics = false
            switch result {
            case let .success(exportResult):
                diagnosticExportStatus = .success(
                    recordCount: exportResult.recordCount,
                    filename: exportResult.destinationURL.lastPathComponent
                )
            case let .failure(error):
                diagnosticExportStatus = .failure(error.localizedDescription)
            }
        }
    }

    private func diagnosticExportMessage(for status: DiagnosticExportStatus) -> String {
        switch status {
        case let .success(recordCount, filename):
            L.settingsDiagnosticExportSuccess(recordCount: recordCount, filename: filename)
        case let .failure(message):
            L.settingsDiagnosticExportFailed(message)
        }
    }

    private static func diagnosticFilenameTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    private enum DiagnosticExportStatus: Equatable, Sendable {
        case success(recordCount: Int, filename: String)
        case failure(String)

        var isSuccess: Bool {
            if case .success = self {
                return true
            }
            return false
        }
    }
}
