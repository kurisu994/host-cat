import HostCatCore
import SwiftUI

/// UI-layer backup entry for display.
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

/// Backup management and restore view.
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
            // Left: backup list
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(L.backupHistory)
                        .font(.headline)
                    Spacer()
                    Button(action: createManualBackup) {
                        Image(systemName: "plus")
                    }
                    .help(L.backupCreateManual)
                    Button(action: refreshBackups) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(L.settingsRefresh)
                }
                .padding(12)

                Divider()

                if backups.isEmpty {
                    VStack {
                        Spacer()
                        Text(L.backupNoBackups)
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

            // Right: preview and actions
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
                        Button(L.backupRestoreThis) {
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
                        Text(L.backupSelectPreview)
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
            errorMessage = L.errorReadBackupFailed
        }
    }

    private func createManualBackup() {
        do {
            let hostsData = try Data(contentsOf: URL(fileURLWithPath: "/etc/hosts"))
            let hostsText = HostsImporter().importHostsWithFallback(data: hostsData).decodedContent
            guard !hostsText.isEmpty else {
                errorMessage = L.errorEmptyHosts
                return
            }
            _ = try backupStore.createBackup(content: hostsText)
            refreshBackups()
        } catch {
            errorMessage = L.backupCreateFailed(error.localizedDescription)
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
                    errorMessage = L.backupRestoreFailed(result.errorMessage ?? L.errorUnknown)
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
        formatter.locale = Locale.current
        return formatter.string(from: createdAt)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }
}
