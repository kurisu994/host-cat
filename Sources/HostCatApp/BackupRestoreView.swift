import HostCatCore
import SwiftUI

/// UI 层展示用的备份条目
struct BackupEntry: Hashable, Identifiable {
    let id = UUID()
    let url: URL
    let createdAt: Date
    let sizeBytes: Int

    init(url: URL) {
        self.url = url
        self.createdAt = BackupStore.extractDate(from: url) ?? Date()
        self.sizeBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    static func == (lhs: BackupEntry, rhs: BackupEntry) -> Bool {
        lhs.url == rhs.url
    }
}

/// 备份管理和恢复视图
struct BackupRestoreView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @State private var backups: [BackupEntry] = []
    @State private var selectedBackup: BackupEntry?
    @State private var previewContent: String?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let backupStore = BackupStore()

    var body: some View {
        HSplitView {
            // 左侧：备份列表
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("备份历史")
                        .font(.headline)
                    Spacer()
                    Button(action: createManualBackup) {
                        Image(systemName: "plus")
                    }
                    .help("手动创建备份")
                    Button(action: refreshBackups) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("刷新列表")
                }
                .padding(12)

                Divider()

                if backups.isEmpty {
                    VStack {
                        Spacer()
                        Text("暂无备份")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List(backups, selection: $selectedBackup) { backup in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(backup.formattedDate)
                                .font(.callout.bold())
                            Text(backup.formattedSize)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .tag(backup)
                    }
                }
            }
            .frame(minWidth: 200, idealWidth: 250)

            // 右侧：预览和操作
            VStack(spacing: 0) {
                if let content = previewContent {
                    ScrollView {
                        Text(content)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Divider()

                    HStack {
                        if let error = errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                        Spacer()
                        Button("恢复此备份") {
                            restoreBackup()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isLoading)
                    }
                    .padding(12)
                } else {
                    VStack {
                        Spacer()
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("选择一个备份来预览")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(minWidth: 400, idealWidth: 500)
        }
        .frame(minHeight: 400)
        .onAppear { refreshBackups() }
        .onChange(of: selectedBackup) { _, newValue in
            loadPreview(for: newValue)
        }
    }

    private func refreshBackups() {
        let urls = backupStore.listBackups()
        backups = urls.map { BackupEntry(url: $0) }
        errorMessage = nil
    }

    private func loadPreview(for backup: BackupEntry?) {
        guard let backup else {
            previewContent = nil
            return
        }
        if let content = backupStore.readBackup(at: backup.url) {
            previewContent = content
            errorMessage = nil
        } else {
            previewContent = nil
            errorMessage = "读取备份文件失败"
        }
    }

    private func createManualBackup() {
        do {
            let hostsData = try Data(contentsOf: URL(fileURLWithPath: "/etc/hosts"))
            let hostsText = HostsImporter().importHostsWithFallback(data: hostsData).decodedContent
            guard !hostsText.isEmpty else {
                errorMessage = "当前 hosts 文件为空"
                return
            }
            _ = try backupStore.createBackup(content: hostsText)
            refreshBackups()
        } catch {
            errorMessage = "创建备份失败: \(error.localizedDescription)"
        }
    }

    private func restoreBackup() {
        guard let content = previewContent else { return }
        isLoading = true
        errorMessage = nil

        Task {
            let result = await viewModel.restoreBackup(content: content)
            await MainActor.run {
                isLoading = false
                if result.success {
                    errorMessage = nil
                    refreshBackups()
                } else {
                    errorMessage = "恢复失败: \(result.errorMessage ?? "未知错误")"
                }
            }
        }
    }
}

private extension BackupEntry {
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh-Hans")
        return formatter.string(from: createdAt)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }
}
