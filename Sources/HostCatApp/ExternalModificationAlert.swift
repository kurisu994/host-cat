import HostCatCore
import SwiftUI

/// 外部修改检测决策弹窗
struct ExternalModificationAlert: ViewModifier {
    @ObservedObject var viewModel: MenuBarViewModel

    func body(content: Content) -> some View {
        content
            .alert("hosts 文件已被外部修改", isPresented: $viewModel.showExternalModificationAlert) {
                Button("取消写入", role: .cancel) {
                    viewModel.applyError = nil
                }
                Button("确认覆盖", role: .destructive) {
                    viewModel.forceApply()
                }
            } message: {
                Text("hosts 文件在 HostCat 之外发生了变化。你可以取消本次写入，或确认覆盖外部修改。")
            }
    }
}

extension View {
    func externalModificationAlert(viewModel: MenuBarViewModel) -> some View {
        modifier(ExternalModificationAlert(viewModel: viewModel))
    }
}
