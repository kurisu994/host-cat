import AppKit
import SwiftUI

/// 悬停时显示的合成 Hosts 预览内容
struct HoverPreviewContent: View {
    let text: String

    private var displayText: String {
        let lines = text.components(separatedBy: .newlines)
        if lines.count > 50 {
            return lines.prefix(50).joined(separator: "\n") + "\n\n" + L.previewTruncated(lines.count)
        }
        return text
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L.previewMergedHosts)
                    .font(.headline)
                Spacer()
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 4)

            Divider()

            ScrollView {
                Text(displayText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }

            Divider()

            HStack {
                Text("\(text.count) " + L.editorLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(L.previewClickFull)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding([.horizontal, .bottom])
            .padding(.top, 4)
        }
        .frame(width: 520, height: 360)
    }
}

/// 在原生菜单跟踪期间展示只读预览，避免菜单项内的 SwiftUI popover 无法呈现。
@MainActor
final class HoverPreviewPanelController: ObservableObject {
    private enum Layout {
        static let size = NSSize(width: 520, height: 360)
        static let pointerSpacing: CGFloat = 14
    }

    private let panel: NSPanel

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Layout.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
    }

    func show(text: String) {
        panel.contentView = NSHostingView(
            rootView: HoverPreviewContent(text: text)
                .background(Color(nsColor: .windowBackgroundColor))
        )
        positionNearPointer()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func positionNearPointer() {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        let width = panel.frame.width
        let height = panel.frame.height
        let rightOriginX = pointer.x + Layout.pointerSpacing
        let preferredX = rightOriginX + width <= visibleFrame.maxX
            ? rightOriginX
            : pointer.x - width - Layout.pointerSpacing
        let x = min(max(preferredX, visibleFrame.minX), visibleFrame.maxX - width)
        let centeredY = pointer.y - height / 2
        let y = min(max(centeredY, visibleFrame.minY), visibleFrame.maxY - height)

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
