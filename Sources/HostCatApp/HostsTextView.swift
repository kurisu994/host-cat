import AppKit
import SwiftUI

/// Bridges NSTextView to SwiftUI as a hosts text editor.
///
/// Replaces SwiftUI TextEditor, providing syntax highlighting, a line-number gutter, and error-line marking.
/// Uses TextKit 2 and the NSScrollView + NSTextView architecture.
struct HostsTextView: NSViewRepresentable {
    @Binding var text: String

    /// Set of error line numbers (1-indexed).
    var errorLines: Set<Int>

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        // Text view configuration
        textView.font = HostsSyntaxHighlighter.defaultFont
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFindBar = true

        // Disable automatic substitutions to preserve plain-text editing experience.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false

        // Content inset
        textView.textContainerInset = NSSize(width: 4, height: 8)

        // Disable word wrapping to allow horizontal scrolling, preserving line-by-line editing semantics for hosts files.
        scrollView.hasHorizontalScroller = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.widthTracksTextView = false

        // Set delegate
        textView.delegate = context.coordinator

        // Initial text and highlighting
        textView.string = text
        HostsSyntaxHighlighter.highlight(textView.textStorage!, errorLines: errorLines)
        context.coordinator.lastHighlightedText = text
        context.coordinator.lastErrorLines = errorLines

        // Configure line-number gutter
        let rulerView = LineNumberRulerView(textView: textView)
        rulerView.errorLines = errorLines
        scrollView.verticalRulerView = rulerView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        // Listen for content view scroll events to refresh line numbers
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        // Save references
        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView
        context.coordinator.rulerView = rulerView
        context.coordinator.syncLayout(resetHorizontalOffset: true, remeasureWidth: true)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only update when text changes externally (avoids cursor jumping during editing).
        var didReplaceText = false
        if textView.string != text {
            context.coordinator.isUpdatingFromSwiftUI = true
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            context.coordinator.isUpdatingFromSwiftUI = false
            didReplaceText = true
        }

        // 文本和错误行都没变时跳过全量高亮（例如仅 isApplying 刷新）。
        let needsHighlight = didReplaceText
            || context.coordinator.lastHighlightedText != text
            || context.coordinator.lastErrorLines != errorLines
        if needsHighlight {
            HostsSyntaxHighlighter.highlight(textView.textStorage!, errorLines: errorLines)
            context.coordinator.lastHighlightedText = text
            context.coordinator.lastErrorLines = errorLines
        }
        context.coordinator.syncLayout(
            resetHorizontalOffset: didReplaceText,
            remeasureWidth: needsHighlight
        )

        // Update line-number gutter error lines
        if let rulerView = scrollView.verticalRulerView as? LineNumberRulerView {
            rulerView.errorLines = errorLines
            rulerView.needsDisplay = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// Syncs document width in non-wrapping mode to prevent infinite container from drawing text into invisible areas.
    /// 非换行布局。宽度按整篇文本测量，结果缓存；滚动只复用缓存，避免每帧扫全部行。
    private static func syncNonWrappingLayout(
        textView: NSTextView,
        in scrollView: NSScrollView,
        resetHorizontalOffset: Bool,
        cachedWidth: inout CGFloat?,
        remeasureWidth: Bool
    ) {
        let documentWidth = resolvedDocumentWidth(
            textView: textView,
            in: scrollView,
            cachedWidth: &cachedWidth,
            remeasureWidth: remeasureWidth
        )
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

    private static func resolvedDocumentWidth(
        textView: NSTextView,
        in scrollView: NSScrollView,
        cachedWidth: inout CGFloat?,
        remeasureWidth: Bool
    ) -> CGFloat {
        if !remeasureWidth, let cachedWidth {
            return cachedWidth
        }
        let width = preferredDocumentWidth(textView: textView, in: scrollView)
        cachedWidth = width
        return width
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

    /// Coordinator: handles NSTextViewDelegate and scroll notifications.
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HostsTextView
        weak var scrollView: NSScrollView?
        weak var textView: NSTextView?
        weak var rulerView: LineNumberRulerView?

        /// Prevents circular triggering between updateNSView and textDidChange.
        var isUpdatingFromSwiftUI = false

        /// 最近一次高亮对应的文本和错误行，用于跳过无变化的全量重绘。
        var lastHighlightedText: String?
        var lastErrorLines: Set<Int>?
        /// 非换行文档宽度缓存。仅文本变化时重测。
        var cachedDocumentWidth: CGFloat?
        /// 滚动会同步发出 bounds 通知。同步布局时忽略重入，避免同时改宽度缓存导致崩溃。
        var isSyncingLayout = false

        func syncLayout(resetHorizontalOffset: Bool, remeasureWidth: Bool) {
            guard !isSyncingLayout, let textView, let scrollView else { return }
            isSyncingLayout = true
            defer { isSyncingLayout = false }
            HostsTextView.syncNonWrappingLayout(
                textView: textView,
                in: scrollView,
                resetHorizontalOffset: resetHorizontalOffset,
                cachedWidth: &cachedDocumentWidth,
                remeasureWidth: remeasureWidth
            )
        }

        init(parent: HostsTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !isUpdatingFromSwiftUI else { return }

            // 写回 binding 后由 updateNSView 做一次高亮和宽度测量，避免按键路径算两遍。
            parent.text = textView.string

            // Refresh line numbers
            rulerView?.needsDisplay = true
        }

        @MainActor
        @objc func boundsDidChange(_: Notification) {
            syncLayout(resetHorizontalOffset: false, remeasureWidth: false)
            rulerView?.needsDisplay = true
        }
    }
}
