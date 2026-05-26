import AppKit

/// Line number gutter that uses NSLayoutManager to locate each line's y-coordinate.
///
/// Mounted on the NSScrollView's verticalRulerView, it automatically refreshes as the text scrolls.
/// Supports current-line highlighting and error-line marking.
final class LineNumberRulerView: NSRulerView {

    // MARK: - Properties

    /// Set of error line numbers (1-indexed) for marking line numbers in red.
    var errorLines: Set<Int> = [] {
        didSet { needsDisplay = true }
    }

    /// Gutter width.
    private let gutterWidth: CGFloat = 48

    /// Line number font.
    private let lineNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    /// Line number text color.
    private let lineNumberColor = NSColor.secondaryLabelColor

    /// Error line number color.
    private let errorLineNumberColor = NSColor.systemRed

    /// Current line highlight color.
    private let currentLineColor = NSColor.labelColor

    /// Error line dot color.
    private let errorDotColor = NSColor.systemRed

    // MARK: - Init

    init(textView: NSTextView) {
        guard let scrollView = textView.enclosingScrollView else {
            fatalError("LineNumberRulerView requires textView to be added to NSScrollView")
        }
        super.init(
            scrollView: scrollView,
            orientation: .verticalRuler
        )
        self.clientView = textView
        self.ruleThickness = gutterWidth

        // Listen for text changes to refresh line numbers.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: NSText.didChangeNotification,
            object: textView
        )

        // Listen for selection changes to highlight the current line.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectionDidChange(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

        // Current selection line (for highlighting the current line number).
        let currentLineNumber = currentLineNumberForSelection(textView: textView)
        let visibleRect = textView.visibleRect
        let textContainerOrigin = textView.textContainerOrigin
        let visibleContainerRect = NSRect(
            // Line numbers only depend on the vertical visible range;
            // horizontal scroll / ruler offset should not affect line number positioning.
            x: 0,
            y: visibleRect.minY - textContainerOrigin.y,
            width: max(textContainer.containerSize.width, visibleRect.width),
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
        let gutterRect = bounds.intersection(rect)
        guard !gutterRect.isEmpty else { return }

        NSColor.controlBackgroundColor.setFill()
        gutterRect.fill()

        let separatorX = bounds.maxX - 0.5
        let separatorPath = NSBezierPath()
        separatorPath.move(to: NSPoint(x: separatorX, y: gutterRect.minY))
        separatorPath.line(to: NSPoint(x: separatorX, y: gutterRect.maxY))
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

    /// Returns the line number of the current selection (1-indexed).
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
