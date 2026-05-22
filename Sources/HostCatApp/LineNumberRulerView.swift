import AppKit

/// 行号 gutter，使用 NSLayoutManager 定位每行的 y 坐标
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
    private let gutterWidth: CGFloat = 48

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
        guard let scrollView = textView.enclosingScrollView else {
            fatalError("LineNumberRulerView 要求 textView 必须已添加到 NSScrollView 中")
        }
        super.init(
            scrollView: scrollView,
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
        drawBackground(in: rect)

        guard let textView = clientView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return }

        // 当前选区所在行（用于高亮当前行号）
        let currentLineNumber = currentLineNumberForSelection(textView: textView)
        let visibleRect = textView.visibleRect
        let textContainerOrigin = textView.textContainerOrigin
        let visibleContainerRect = NSRect(
            x: visibleRect.minX - textContainerOrigin.x,
            y: visibleRect.minY - textContainerOrigin.y,
            width: visibleRect.width,
            height: visibleRect.height
        )

        layoutManager.ensureLayout(for: textContainer)

        if layoutManager.numberOfGlyphs == 0 {
            drawLineNumber(
                1,
                lineY: textContainerOrigin.y - visibleRect.minY,
                lineHeight: lineNumberFont.boundingRectForFont.height,
                isCurrentLine: currentLineNumber == 1
            )
            return
        }

        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleContainerRect, in: textContainer)
        var lineNumber = lineNumberForGlyph(at: glyphRange.location, layoutManager: layoutManager, textView: textView)

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
            let lineY = textContainerOrigin.y + usedRect.minY - visibleRect.minY
            self.drawLineNumber(
                lineNumber,
                lineY: lineY,
                lineHeight: usedRect.height,
                isCurrentLine: lineNumber == currentLineNumber
            )
            lineNumber += 1
        }
    }

    // MARK: - Private

    private func drawBackground(in rect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        rect.fill()

        let separatorX = bounds.maxX - 0.5
        let separatorPath = NSBezierPath()
        separatorPath.move(to: NSPoint(x: separatorX, y: rect.minY))
        separatorPath.line(to: NSPoint(x: separatorX, y: rect.maxY))
        separatorPath.lineWidth = 0.5
        NSColor.separatorColor.setStroke()
        separatorPath.stroke()
    }

    private func drawLineNumber(
        _ lineNumber: Int,
        lineY: CGFloat,
        lineHeight: CGFloat,
        isCurrentLine: Bool
    ) {
        let isErrorLine = errorLines.contains(lineNumber)
        let color: NSColor
        if isCurrentLine {
            color = currentLineColor
        } else if isErrorLine {
            color = errorLineNumberColor
        } else {
            color = lineNumberColor
        }

        let font = isCurrentLine
            ? NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            : lineNumberFont
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let lineStr = "\(lineNumber)" as NSString
        let strSize = lineStr.size(withAttributes: attrs)
        let x = bounds.width - strSize.width - 10
        let y = lineY + (lineHeight - strSize.height) / 2

        lineStr.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)

        if isErrorLine {
            let dotSize: CGFloat = 4
            let dotY = lineY + (lineHeight - dotSize) / 2
            let dotRect = NSRect(x: 6, y: dotY, width: dotSize, height: dotSize)
            errorDotColor.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }
    }

    private func lineNumberForGlyph(
        at glyphIndex: Int,
        layoutManager: NSLayoutManager,
        textView: NSTextView
    ) -> Int {
        guard layoutManager.numberOfGlyphs > 0 else { return 1 }
        let safeGlyphIndex = min(glyphIndex, layoutManager.numberOfGlyphs - 1)
        let characterIndex = layoutManager.characterIndexForGlyph(at: safeGlyphIndex)
        return lineNumber(atCharacterIndex: characterIndex, in: textView.string)
    }

    /// 获取当前选区所在的行号（1-indexed）
    private func currentLineNumberForSelection(textView: NSTextView) -> Int? {
        let selectedRange = textView.selectedRange()
        guard selectedRange.location != NSNotFound else { return nil }

        let documentLength = (textView.string as NSString).length
        let characterIndex = min(selectedRange.location, documentLength)
        return lineNumber(atCharacterIndex: characterIndex, in: textView.string)
    }

    private func lineNumber(atCharacterIndex characterIndex: Int, in text: String) -> Int {
        let nsString = text as NSString
        guard characterIndex > 0, nsString.length > 0 else { return 1 }

        var lineNumber = 1
        let upperBound = min(characterIndex, nsString.length)
        for index in 0..<upperBound where nsString.character(at: index) == 10 {
            lineNumber += 1
        }
        return lineNumber
    }

    // MARK: - Notifications

    @objc private func textDidChange(_: Notification) {
        needsDisplay = true
    }

    @objc private func selectionDidChange(_: Notification) {
        needsDisplay = true
    }
}
