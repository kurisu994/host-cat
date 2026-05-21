import HostCatCore
import SwiftUI
import UniformTypeIdentifiers

/// 节点拖拽排序代理，支持分组内节点实时重排动画
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
        // 拖出范围时不清除，等 performDrop 处理
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggingNodeID != nil
    }
}
