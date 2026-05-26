import HostCatCore
import SwiftUI

/// Alert for external modification detection decisions.
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
