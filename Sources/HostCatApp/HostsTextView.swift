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

        // 关闭自动换行，允许水平滚动，保留 hosts 文件的一行一行编辑语义。
        scrollView.hasHorizontalScroller = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.widthTracksTextView = false

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
        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView
        context.coordinator.rulerView = rulerView
        Self.syncNonWrappingLayout(textView: textView, in: scrollView, resetHorizontalOffset: true)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // 仅在外部 text 变化时更新（避免编辑时光标跳动）
        var didReplaceText = false
        if textView.string != text {
            context.coordinator.isUpdatingFromSwiftUI = true
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            context.coordinator.isUpdatingFromSwiftUI = false
            didReplaceText = true
        }

        // 更新高亮和错误行
        HostsSyntaxHighlighter.highlight(textView.textStorage!, errorLines: errorLines)
        Self.syncNonWrappingLayout(
            textView: textView,
            in: scrollView,
            resetHorizontalOffset: didReplaceText
        )

        // 更新行号 gutter 错误行
        if let rulerView = scrollView.verticalRulerView as? LineNumberRulerView {
            rulerView.errorLines = errorLines
            rulerView.needsDisplay = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// 同步非自动换行模式下的文档宽度，避免无限 container 让文本绘制到不可见区域。
    private static func syncNonWrappingLayout(
        textView: NSTextView,
        in scrollView: NSScrollView,
        resetHorizontalOffset: Bool
    ) {
        let documentWidth = preferredDocumentWidth(textView: textView, in: scrollView)
        textView.textContainer?.containerSize = NSSize(
            width: documentWidth,
            height: CGFloat.greatestFiniteMagnitude
        )

        var documentHeight = max(scrollView.contentSize.height, textView.frame.height)
        if let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = layoutManager.usedRect(for: textContainer).height
            documentHeight = max(documentHeight, ceil(usedHeight + textView.textContainerInset.height * 2))
        }

        let newSize = NSSize(width: documentWidth, height: documentHeight)
        if textView.frame.size != newSize {
            textView.setFrameSize(newSize)
        }

        if resetHorizontalOffset {
            resetHorizontalScroll(in: scrollView)
        }
    }

    private static func preferredDocumentWidth(textView: NSTextView, in scrollView: NSScrollView) -> CGFloat {
        let font = textView.font ?? HostsSyntaxHighlighter.defaultFont
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let nsString = textView.string as NSString
        var widestLine: CGFloat = 0
        var lineStart = 0

        while lineStart < nsString.length {
            var lineEnd = 0
            var contentsEnd = 0
            nsString.getLineStart(
                nil,
                end: &lineEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: lineStart, length: 0)
            )

            let lineRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
            let line = nsString.substring(with: lineRange) as NSString
            widestLine = max(widestLine, ceil(line.size(withAttributes: attrs).width))
            lineStart = lineEnd
        }

        let horizontalInset = textView.textContainerInset.width * 2
        let linePadding = (textView.textContainer?.lineFragmentPadding ?? 0) * 2
        let visibleWidth = max(scrollView.contentSize.width, scrollView.bounds.width, 400)
        return max(visibleWidth, widestLine + horizontalInset + linePadding + 32)
    }

    private static func resetHorizontalScroll(in scrollView: NSScrollView) {
        let rulerOffset: CGFloat
        if scrollView.hasVerticalRuler, scrollView.rulersVisible {
            rulerOffset = scrollView.verticalRulerView?.ruleThickness ?? 0
        } else {
            rulerOffset = 0
        }

        let currentY = scrollView.contentView.bounds.origin.y
        scrollView.contentView.scroll(to: NSPoint(x: -rulerOffset, y: currentY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - Coordinator

    /// 协调器：处理 NSTextViewDelegate 和滚动通知
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HostsTextView
        weak var scrollView: NSScrollView?
        weak var textView: NSTextView?
        weak var rulerView: LineNumberRulerView?

        /// 防止 updateNSView 和 textDidChange 循环触发
        var isUpdatingFromSwiftUI = false

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
            if let scrollView {
                HostsTextView.syncNonWrappingLayout(
                    textView: textView,
                    in: scrollView,
                    resetHorizontalOffset: false
                )
            }

            // 刷新行号
            rulerView?.needsDisplay = true
        }

        @MainActor
        @objc func boundsDidChange(_: Notification) {
            if let textView, let scrollView {
                HostsTextView.syncNonWrappingLayout(
                    textView: textView,
                    in: scrollView,
                    resetHorizontalOffset: false
                )
            }
            rulerView?.needsDisplay = true
        }
    }
}
