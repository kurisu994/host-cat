import HostCatCore
import HostCatHelperClient
import ServiceManagement
import SwiftUI

/// 当 Apply 因 Privileged Helper 未注册或未审批而失败时，
/// 向用户呈现可操作的对话框：根据当前 helper 状态切换主按钮，
/// 完成后调用 `MenuBarViewModel.retryApplyAfterHelperRecovery()` 重新写入。
struct HelperRecoveryAlert: ViewModifier {
    @ObservedObject var viewModel: MenuBarViewModel
    @ObservedObject var registrationManager: HelperRegistrationManager

    func body(content: Content) -> some View {
        content
            .alert(
                LC.helperRecoveryTitle,
                isPresented: isPresentedBinding,
                presenting: viewModel.helperRecoveryPrompt
            ) { prompt in
                actionButtons(for: prompt)
            } message: { prompt in
                Text(LC.helperRecoveryMessage(reason: prompt.errorMessage))
            }
            .onChange(of: viewModel.helperRecoveryPrompt) { _, newValue in
                // 弹出前刷新一次状态，避免 UI 上显示过期的「未注册」。
                guard newValue != nil else { return }
                registrationManager.refreshHelperStatus()
            }
    }

    /// 把 `helperRecoveryPrompt?` 包装成 `.alert(isPresented:)` 需要的 Bool 绑定。
    /// 用户主动 dismiss 时清空 prompt，避免下次还误弹。
    private var isPresentedBinding: Binding<Bool> {
        Binding(
            get: { viewModel.helperRecoveryPrompt != nil },
            set: { newValue in
                if !newValue {
                    viewModel.dismissHelperRecoveryPrompt()
                }
            }
        )
    }

    /// 根据 helper 当前状态决定首选恢复动作；最后总有「取消」。
    @ViewBuilder
    private func actionButtons(for _: HelperRecoveryPrompt) -> some View {
        switch registrationManager.helperStatus {
        case .requiresApproval:
            Button(L.helperOpenSettings) {
                registrationManager.openSystemSettings()
            }
            Button(L.helperRecoveryRetry) {
                Task { await viewModel.retryApplyAfterHelperRecovery() }
            }
        case .enabled:
            // 状态显示已启用但写入失败，说明 XPC 连接瞬时断了，给个直接重试。
            Button(L.helperRecoveryRetry) {
                Task { await viewModel.retryApplyAfterHelperRecovery() }
            }
        default:
            // notRegistered / notFound / 未来新枚举值都走「安装 Helper」。
            Button(L.helperInstall) {
                registrationManager.registerHelper()
                // 注册后若 macOS 把状态推进到 requiresApproval，
                // 立刻引导用户去系统设置开关；避免用户再点一次。
                if registrationManager.helperStatus == .requiresApproval {
                    registrationManager.openSystemSettings()
                } else if registrationManager.helperStatus == .enabled {
                    Task { await viewModel.retryApplyAfterHelperRecovery() }
                }
            }
        }

        Button(L.helperRecoveryDismiss, role: .cancel) {
            viewModel.dismissHelperRecoveryPrompt()
        }
    }
}

extension View {
    /// 在任意承载 MenuBarViewModel 的视图上挂载 helper 恢复引导。
    func helperRecoveryAlert(
        viewModel: MenuBarViewModel,
        registrationManager: HelperRegistrationManager
    ) -> some View {
        modifier(HelperRecoveryAlert(viewModel: viewModel, registrationManager: registrationManager))
    }
}
