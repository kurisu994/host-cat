import HostCatCore
import HostCatHelperClient
import SwiftUI

/// Helper 注册和审批引导视图
struct HelperSetupView: View {
    @ObservedObject var registrationManager: HelperRegistrationManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            // 标题
            VStack(spacing: 8) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text(L.helperSetupTitle)
                    .font(.title2.bold())
                Text(L.helperSetupDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // 状态
            GroupBox {
                HStack {
                    Text(L.helperCurrentStatus)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 10, height: 10)
                        Text(registrationManager.helperStatusDescription)
                            .fontWeight(.medium)
                    }
                }
                .padding(.vertical, 4)
            }

            // 操作按钮
            VStack(spacing: 12) {
                switch registrationManager.helperStatus {
                case .notRegistered, .notFound:
                    Button(action: { registrationManager.registerHelper() }) {
                        Label(L.helperRegister, systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)

                    Text(L.helperRegisterHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .requiresApproval:
                    VStack(spacing: 8) {
                        Label(L.helperPendingApproval, systemImage: "clock.badge.checkmark")
                            .foregroundStyle(.orange)

                        Button(action: { registrationManager.openSystemSettings() }) {
                            Label(L.helperOpenSettings, systemImage: "gear")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)

                        Button(L.editorRefresh) {
                            registrationManager.refreshHelperStatus()
                        }
                        .controlSize(.small)
                    }

                case .enabled:
                    Label(L.helperEnabled, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout.bold())

                    Button(L.dialogDone) {
                        dismiss()
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)

                @unknown default:
                    Text(L.errorUnknown)
                        .foregroundStyle(.secondary)
                }
            }

            // 错误信息
            if let error = registrationManager.lastError {
                GroupBox {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .padding(32)
        .frame(width: 400)
        .onAppear {
            registrationManager.refreshHelperStatus()
        }
    }

    private var statusColor: Color {
        switch registrationManager.helperStatus {
        case .enabled: .green
        case .requiresApproval: .yellow
        default: .red
        }
    }
}
