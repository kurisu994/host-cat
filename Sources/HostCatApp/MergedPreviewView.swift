import HostCatCore
import SwiftUI

struct MergedPreviewView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Text("合成 Hosts 预览")
                    .font(.headline)

                Spacer()

                if viewModel.lastDuplicateCount > 0 {
                    Label("\(viewModel.lastDuplicateCount) 条重复已合并", systemImage: "arrow.triangle.merge")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("刷新") {
                    viewModel.updateMergedPreview()
                }
            }
            .padding()

            Divider()

            // 冲突提示
            if !viewModel.lastConflicts.isEmpty {
                ConflictBanner(conflicts: viewModel.lastConflicts) { conflict in
                    // TODO: 导航到冲突节点需要 EditorView 集成，当前显示提示
                    viewModel.applyError = "冲突节点 \(conflict.hostname) 位于 \(conflict.incoming.nodeName)"
                }
            }

            // 文本预览
            if let text = viewModel.lastMergedText {
                ScrollView {
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(Color(NSColor.textBackgroundColor))
            } else {
                ContentUnavailableView("暂无合成内容", systemImage: "doc.text")
            }

            // 状态栏
            HStack {
                if viewModel.isApplying {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在应用...")
                        .font(.caption)
                }

                if let error = viewModel.applyError {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()

                if let text = viewModel.lastMergedText {
                    Text("\(text.count) 字符")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            viewModel.updateMergedPreview()
        }
    }
}

// MARK: - Conflict Banner

struct ConflictBanner: View {
    let conflicts: [HostConflict]
    let onNavigate: (HostConflict) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("检测到 \(conflicts.count) 个冲突")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text("请修改节点内容或停用冲突节点后重新应用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(conflicts, id: \.hostname) { conflict in
                ConflictRow(conflict: conflict) {
                    onNavigate(conflict)
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

struct ConflictRow: View {
    let conflict: HostConflict
    let onNavigate: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(conflict.hostname)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)

                HStack(spacing: 16) {
                    ConflictEndpointLabel(
                        label: "已有",
                        ip: conflict.existing.ipAddress,
                        source: conflict.existing.nodeName
                    )

                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ConflictEndpointLabel(
                        label: "冲突",
                        ip: conflict.incoming.ipAddress,
                        source: conflict.incoming.nodeName
                    )
                }
            }

            Spacer()

            Button("定位") {
                onNavigate()
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

struct ConflictEndpointLabel: View {
    let label: String
    let ip: String
    let source: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(ip)
                .font(.caption)
                .fontWeight(.medium)
            Text("(\(source))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
