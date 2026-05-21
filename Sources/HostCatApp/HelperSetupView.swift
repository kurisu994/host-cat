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
                Text("Privileged Helper 设置")
                    .font(.title2.bold())
                Text("HostCat 需要安装一个 Helper 来安全地修改 /etc/hosts 文件")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // 状态
            GroupBox {
                HStack {
                    Text("当前状态")
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
                        Label("注册 Helper", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)

                    Text("注册后需要在「系统设置 > 通用 > 登录项」中启用")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .requiresApproval:
                    VStack(spacing: 8) {
                        Label("Helper 已注册，等待系统审批", systemImage: "clock.badge.checkmark")
                            .foregroundStyle(.orange)

                        Button(action: { registrationManager.openSystemSettings() }) {
                            Label("打开系统设置", systemImage: "gear")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)

                        Button("刷新状态") {
                            registrationManager.refreshHelperStatus()
                        }
                        .controlSize(.small)
                    }

                case .enabled:
                    Label("Helper 已启用，可以正常使用", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout.bold())

                    Button("完成") {
                        dismiss()
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)

                @unknown default:
                    Text("未知状态")
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
