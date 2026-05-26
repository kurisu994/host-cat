import HostCatCore
import SwiftUI

/// 外部修改检测决策弹窗
struct ExternalModificationAlert: ViewModifier {
    @ObservedObject var viewModel: MenuBarViewModel

    func body(content: Content) -> some View {
        content
            .alert(L.errorExternalModification, isPresented: $viewModel.showExternalModificationAlert) {
                Button(L.editorDiscard, role: .cancel) {
                    viewModel.applyError = nil
                }
                Button(L.errorOverwrite, role: .destructive) {
                    viewModel.forceApply()
                }
            } message: {
                Text(L.errorExternalModificationMessage)
            }
    }
}

extension View {
    func externalModificationAlert(viewModel: MenuBarViewModel) -> some View {
        modifier(ExternalModificationAlert(viewModel: viewModel))
    }
}
