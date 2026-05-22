import AppKit
import HostCatCore

/// hosts 文件语法高亮引擎
///
/// 对 NSTextStorage 进行全量逐行高亮，识别以下元素：
/// - HostCat 管理区块标记行（橙色粗体）
/// - 纯注释行（灰色）
/// - IP 地址（蓝色）
/// - hostname（绿色）
/// - 行尾注释（灰色）
/// - 错误行（红色半透明背景）
@MainActor
struct HostsSyntaxHighlighter {
    /// 默认等宽字体
    static let defaultFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    /// 高亮配色
    struct Colors {
        static let comment = NSColor.secondaryLabelColor
        static let ipAddress = NSColor.systemBlue
        static let hostname = NSColor.systemGreen
        static let marker = NSColor.systemOrange
        static let errorBackground = NSColor.systemRed.withAlphaComponent(0.1)
        static let defaultText = NSColor.labelColor
    }

    /// 对整个 textStorage 执行全量语法高亮
    /// - Parameters:
    ///   - textStorage: 要高亮的文本存储
    ///   - errorLines: parser 检测到的错误行号集合（1-indexed）
    static func highlight(_ textStorage: NSTextStorage, errorLines: Set<Int>) {
        let text = textStorage.string
        guard !text.isEmpty else { return }

        let fullRange = NSRange(location: 0, length: textStorage.length)

        textStorage.beginEditing()

        // 1. 重置为默认样式
        let defaultAttrs: [NSAttributedString.Key: Any] = [
            .font: defaultFont,
            .foregroundColor: Colors.defaultText,
        ]
        textStorage.setAttributes(defaultAttrs, range: fullRange)

        // 2. 逐行应用高亮
        let nsString = text as NSString
        var lineStart = 0

        for lineNumber in 1... {
            guard lineStart < nsString.length else { break }

            var lineEnd = 0
            var contentsEnd = 0
            nsString.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: lineStart, length: 0))

            let lineRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
            let fullLineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
            let lineContent = nsString.substring(with: lineRange)

            highlightLine(
                lineContent,
                lineRange: lineRange,
                lineNumber: lineNumber,
                isError: errorLines.contains(lineNumber),
                textStorage: textStorage,
                fullLineRange: fullLineRange
            )

            lineStart = lineEnd
            if lineEnd == lineStart && lineStart >= nsString.length {
                break
            }
        }

        textStorage.endEditing()
    }

    // MARK: - Private

    private static func highlightLine(
        _ line: String,
        lineRange: NSRange,
        lineNumber: Int,
        isError: Bool,
        textStorage: NSTextStorage,
        fullLineRange: NSRange
    ) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // 错误行背景
        if isError {
            textStorage.addAttribute(.backgroundColor, value: Colors.errorBackground, range: fullLineRange)
        }

        // HostCat 管理区块标记行
        if trimmed.hasPrefix(HostsImporter.beginMarkerPrefix) || trimmed == HostsImporter.endMarker {
            let markerAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: Colors.marker,
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold),
            ]
            textStorage.addAttributes(markerAttrs, range: lineRange)
            return
        }

        // 纯注释行
        if trimmed.hasPrefix("#") {
            textStorage.addAttribute(.foregroundColor, value: Colors.comment, range: lineRange)
            return
        }

        // 空行跳过
        guard !trimmed.isEmpty else { return }

        // 数据行：IP hostname [alias...] [# comment]
        highlightDataLine(line, lineRange: lineRange, textStorage: textStorage)
    }

    /// 高亮数据行：IP 蓝色、hostname 绿色、行尾注释灰色
    private static func highlightDataLine(
        _ line: String,
        lineRange: NSRange,
        textStorage: NSTextStorage
    ) {
        let nsLine = line as NSString

        // 查找行尾注释
        var bodyPart = line
        if let commentStart = findCommentStart(in: line) {
            let commentNSRange = NSRange(
                location: lineRange.location + commentStart,
                length: nsLine.length - commentStart
            )
            textStorage.addAttribute(.foregroundColor, value: Colors.comment, range: commentNSRange)
            bodyPart = String(line.prefix(commentStart))
        }

        // 拆分 token
        let tokens = tokenize(bodyPart)
        guard let firstToken = tokens.first else { return }

        // 第一个 token 作为 IP
        let ipRange = NSRange(
            location: lineRange.location + firstToken.offset,
            length: firstToken.length
        )
        textStorage.addAttribute(.foregroundColor, value: Colors.ipAddress, range: ipRange)

        // 其余 token 作为 hostname
        for token in tokens.dropFirst() {
            let hostnameRange = NSRange(
                location: lineRange.location + token.offset,
                length: token.length
            )
            textStorage.addAttribute(.foregroundColor, value: Colors.hostname, range: hostnameRange)
        }
    }

    /// 查找行中 `#` 注释开始位置（忽略 IP 地址中可能出现的特殊字符）
    private static func findCommentStart(in line: String) -> Int? {
        // hosts 格式中 `#` 总是注释开始，不存在转义
        guard let range = line.range(of: "#") else { return nil }
        return line.distance(from: line.startIndex, to: range.lowerBound)
    }

    /// Token 位置信息
    private struct Token {
        let offset: Int
        let length: Int
    }

    /// 拆分文本为空白分隔的 token，记录每个 token 在原文中的偏移量
    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        let end = text.endIndex

        while index < end {
            // 跳过空白
            while index < end && (text[index] == " " || text[index] == "\t") {
                index = text.index(after: index)
            }

            guard index < end else { break }

            // 记录 token 开始
            let tokenStart = index

            // 读取非空白字符
            while index < end && text[index] != " " && text[index] != "\t" {
                index = text.index(after: index)
            }

            let offset = text.distance(from: text.startIndex, to: tokenStart)
            let length = text.distance(from: tokenStart, to: index)
            tokens.append(Token(offset: offset, length: length))
        }

        return tokens
    }
}
