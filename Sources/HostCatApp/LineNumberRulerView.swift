import AppKit

/// 行号 gutter，使用 TextKit 2 的 NSTextLayoutManager 定位每行的 y 坐标
///
/// 挂载到 NSScrollView 的 verticalRulerView 上，随文本滚动自动刷新。
/// 支持当前行高亮和错误行标记。
final class LineNumberRulerView: NSRulerView {

    // MARK: - Properties

    /// 错误行号集合（1-indexed），用于标记红色行号
    var errorLines: Set<Int> = [] {
        didSet { needsDisplay = true }
    }

    /// gutter 宽度
    private let gutterWidth: CGFloat = 44

    /// 行号字体
    private let lineNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    /// 行号文字颜色
    private let lineNumberColor = NSColor.secondaryLabelColor

    /// 错误行号颜色
    private let errorLineNumberColor = NSColor.systemRed

    /// 当前行高亮颜色
    private let currentLineColor = NSColor.labelColor

    /// 错误行圆点颜色
    private let errorDotColor = NSColor.systemRed

    // MARK: - Init

    init(textView: NSTextView) {
        super.init(
            scrollView: textView.enclosingScrollView!,
            orientation: .verticalRuler
        )
        self.clientView = textView
        self.ruleThickness = gutterWidth

        // 监听文本视图变化，刷新行号
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: NSText.didChangeNotification,
            object: textView
        )

        // 监听选区变化，高亮当前行
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectionDidChange(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Drawing

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientView as? NSTextView,
              let textLayoutManager = textView.textLayoutManager,
              let textContentManager = textLayoutManager.textContentManager
        else { return }

        // 背景
        let bgColor = NSColor.controlBackgroundColor
        bgColor.setFill()
        rect.fill()

        // 右侧分隔线
        let separatorColor = NSColor.separatorColor
        separatorColor.setStroke()
        let separatorX = bounds.maxX - 0.5
        let separatorPath = NSBezierPath()
        separatorPath.move(to: NSPoint(x: separatorX, y: rect.minY))
        separatorPath.line(to: NSPoint(x: separatorX, y: rect.maxY))
        separatorPath.lineWidth = 0.5
        separatorPath.stroke()

        // 当前选区所在行（用于高亮当前行号）
        let currentLineNumber = currentLineNumberForSelection(textView: textView)

        // 可见区域偏移
        let visibleRect = scrollView?.contentView.bounds ?? .zero
        let yOffset = visibleRect.origin.y

        // 遍历 text layout fragments 计算行号
        var lineNumber = 1
        textLayoutManager.enumerateTextLayoutFragments(
            from: textContentManager.documentRange.location,
            options: [.ensuresLayout, .ensuresExtraLineFragment]
        ) { fragment in
            let fragmentFrame = fragment.layoutFragmentFrame

            // 跳过不在可见区域的 fragment
            let lineY = fragmentFrame.origin.y - yOffset
            guard lineY + fragmentFrame.height >= rect.minY,
                  lineY <= rect.maxY else {
                lineNumber += 1
                return true
            }

            // 确定行号颜色
            let color: NSColor
            if lineNumber == currentLineNumber {
                color = currentLineColor
            } else if errorLines.contains(lineNumber) {
                color = errorLineNumberColor
            } else {
                color = lineNumberColor
            }

            // 确定字体粗细
            let font: NSFont
            if lineNumber == currentLineNumber {
                font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            } else {
                font = lineNumberFont
            }

            // 绘制行号
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
            ]
            let lineStr = "\(lineNumber)" as NSString
            let strSize = lineStr.size(withAttributes: attrs)

            // 右对齐，留 8pt 右边距
            let x = gutterWidth - strSize.width - 8
            let y = lineY + (fragmentFrame.height - strSize.height) / 2

            lineStr.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)

            // 错误行：绘制红色圆点
            if errorLines.contains(lineNumber) {
                let dotSize: CGFloat = 4
                let dotX: CGFloat = 4
                let dotY = lineY + (fragmentFrame.height - dotSize) / 2
                let dotRect = NSRect(x: dotX, y: dotY, width: dotSize, height: dotSize)
                errorDotColor.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }

            lineNumber += 1
            return true
        }
    }

    // MARK: - Private

    /// 获取当前选区所在的行号（1-indexed）
    private func currentLineNumberForSelection(textView: NSTextView) -> Int? {
        guard let textLayoutManager = textView.textLayoutManager,
              let textContentManager = textLayoutManager.textContentManager else { return nil }

        let selectedRange = textView.selectedRange()
        guard selectedRange.location != NSNotFound else { return nil }

        let documentLength = (textView.string as NSString).length

        // 遍历 fragments 找到选区所在行
        var lineNumber = 1
        var foundLine: Int?
        textLayoutManager.enumerateTextLayoutFragments(
            from: textContentManager.documentRange.location,
            options: [.ensuresLayout, .ensuresExtraLineFragment]
        ) { fragment in
            let fragmentRange = fragment.rangeInElement
            let startOffset = textContentManager.offset(
                from: textContentManager.documentRange.location,
                to: fragmentRange.location
            )
            let endOffset = textContentManager.offset(
                from: textContentManager.documentRange.location,
                to: fragmentRange.endLocation
            )
            let isInLine = selectedRange.location >= startOffset &&
                (selectedRange.location < endOffset ||
                    (selectedRange.location == documentLength && selectedRange.location == endOffset))
            if isInLine {
                foundLine = lineNumber
                return false
            }
            lineNumber += 1
            return true
        }

        return foundLine
    }

    // MARK: - Notifications

    @objc private func textDidChange(_: Notification) {
        needsDisplay = true
    }

    @objc private func selectionDidChange(_: Notification) {
        needsDisplay = true
    }
}
