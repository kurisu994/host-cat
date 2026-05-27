import HostCatCore
import SwiftUI

struct MergedPreviewView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text(L.previewMergedHosts)
                    .font(.headline)

                Spacer()

                if viewModel.lastDuplicateCount > 0 {
                    Label(L.previewMergedDuplicatesCount(viewModel.lastDuplicateCount), systemImage: "arrow.triangle.merge")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(L.previewRefresh) {
                    viewModel.updateMergedPreview()
                }

                Button(L.previewApply) {
                    Task {
                        _ = await viewModel.applyImmediately()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isApplying || !viewModel.lastConflicts.isEmpty)
            }
            .padding()

            Divider()

            // Conflict banner
            if !viewModel.lastConflicts.isEmpty {
                ConflictBanner(conflicts: viewModel.lastConflicts) { conflict in
                    // TODO: Navigating to the conflict node requires EditorView integration; currently shows a hint.
                    viewModel.applyError = L.previewConflictLocation(
                        hostname: conflict.hostname,
                        nodeName: conflict.incoming.nodeName
                    )
                }
            }

            // Text preview
            if let text = viewModel.lastMergedText {
                ScrollView {
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(Color(NSColor.textBackgroundColor))
            } else {
                ContentUnavailableView(L.previewNoContent, systemImage: "doc.text")
            }

            // Status bar
            HStack {
                if viewModel.isApplying {
                    ProgressView()
                        .controlSize(.small)
                    Text(L.editorApplying)
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
                    Text(L.editorCharactersCount(text.count))
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
                Text(L.previewConflictsCount(conflicts.count))
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text(L.previewConflictHint)
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
                        label: L.previewExisting,
                        ip: conflict.existing.ipAddress,
                        source: conflict.existing.nodeName
                    )

                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ConflictEndpointLabel(
                        label: L.previewConflicting,
                        ip: conflict.incoming.ipAddress,
                        source: conflict.incoming.nodeName
                    )
                }
            }

            Spacer()

            Button(L.previewShowConflictDetails) {
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
