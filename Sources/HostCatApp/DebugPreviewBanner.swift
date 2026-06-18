import SwiftUI

/// Debug 构建警告横幅。
///
/// 在 Debug 包里 `HostCatApp` 会把 helper client 替换成 `PreviewHostHelperClient`，
/// 调用方看到的是假的"写入成功"，但 `/etc/hosts` 永远不会变。
/// 这里在所有窗口顶部贴一条黄色提示，提醒开发者当前不会真实写入。
///
/// Release 构建里此 modifier 是 no-op，不增加任何视图层级。
struct DebugPreviewBanner: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("DEBUG 模式：写入未真正落盘到 /etc/hosts，请用 Release 构建验证生效。")
                    .font(.callout.weight(.medium))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.yellow.opacity(0.92))
            .foregroundStyle(Color.black)

            content
        }
        #else
        content
        #endif
    }
}

extension View {
    /// 在视图顶部叠加 Debug 写入未落盘的警告横幅；Release 构建无副作用。
    func debugPreviewBanner() -> some View {
        modifier(DebugPreviewBanner())
    }
}
