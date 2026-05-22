import AppKit
import SwiftUI

/// 桥接 NSTextView 到 SwiftUI 的 hosts 文本编辑器
///
/// 替换 SwiftUI TextEditor，提供语法高亮、行号 gutter 和错误行标记。
/// 使用 TextKit 2 和 NSScrollView + NSTextView 架构。
struct HostsTextView: NSViewRepresentable {
    @Binding var text: String

    /// 错误行号集合（1-indexed）
    var errorLines: Set<Int>

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        // 文本视图配置
        textView.font = HostsSyntaxHighlighter.defaultFont
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFindBar = true

        // 禁用自动替换，保持纯文本编辑体验
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false

        // 内容边距
        textView.textContainerInset = NSSize(width: 4, height: 8)

        // 自动换行关闭，允许水平滚动
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        // 设置 delegate
        textView.delegate = context.coordinator

        // 初始文本和高亮
        textView.string = text
        HostsSyntaxHighlighter.highlight(textView.textStorage!, errorLines: errorLines)

        // 配置行号 gutter
        let rulerView = LineNumberRulerView(textView: textView)
        rulerView.errorLines = errorLines
        scrollView.verticalRulerView = rulerView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        // 监听内容视图滚动，同步刷新行号
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        // 保存引用
        context.coordinator.textView = textView
        context.coordinator.rulerView = rulerView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // 仅在外部 text 变化时更新（避免编辑时光标跳动）
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }

        // 更新高亮和错误行
        HostsSyntaxHighlighter.highlight(textView.textStorage!, errorLines: errorLines)

        // 更新行号 gutter 错误行
        if let rulerView = scrollView.verticalRulerView as? LineNumberRulerView {
            rulerView.errorLines = errorLines
            rulerView.needsDisplay = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Coordinator

    /// 协调器：处理 NSTextViewDelegate 和滚动通知
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HostsTextView
        weak var textView: NSTextView?
        weak var rulerView: LineNumberRulerView?

        /// 防止 updateNSView 和 textDidChange 循环触发
        private var isUpdatingFromSwiftUI = false

        init(parent: HostsTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !isUpdatingFromSwiftUI else { return }

            // 回写 text 到 SwiftUI binding
            parent.text = textView.string

            // 实时高亮
            HostsSyntaxHighlighter.highlight(textView.textStorage!, errorLines: parent.errorLines)

            // 刷新行号
            rulerView?.needsDisplay = true
        }

        @objc func boundsDidChange(_: Notification) {
            rulerView?.needsDisplay = true
        }
    }
}
