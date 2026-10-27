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
        // 配置在拖动途中就已改变；拖到列表外松手时 performDrop 不会触发，
        // 所以每次重排都排一次防抖写入，保证界面顺序和落盘配置一致。
        viewModel.scheduleApply()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingNodeID = nil
        return true
    }

    func dropExited(info: DropInfo) {
        // Do not clear when exiting the drop area; let performDrop handle it.
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggingNodeID != nil
    }
}
