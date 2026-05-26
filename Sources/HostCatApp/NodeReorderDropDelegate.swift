import HostCatCore
import SwiftUI
import UniformTypeIdentifiers

/// Node drag-and-drop reorder delegate, supporting real-time reordering animation within groups.
struct NodeReorderDropDelegate: DropDelegate {
    let targetNodeID: UUID
    let groupID: UUID
    @Binding var draggingNodeID: UUID?
    let viewModel: MenuBarViewModel

    func dropEntered(info: DropInfo) {
        guard let draggingID = draggingNodeID,
              draggingID != targetNodeID,
              let groupIndex = viewModel.config.groups.firstIndex(where: { $0.id == groupID }),
              let fromIndex = viewModel.config.groups[groupIndex].nodes.firstIndex(where: { $0.id == draggingID }),
              let toIndex = viewModel.config.groups[groupIndex].nodes.firstIndex(where: { $0.id == targetNodeID })
        else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.config.groups[groupIndex].nodes.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingNodeID = nil
        viewModel.scheduleApply()
        return true
    }

    func dropExited(info: DropInfo) {
        // Do not clear when exiting the drop area; let performDrop handle it.
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggingNodeID != nil
    }
}
