import AppKit
import HostCatCore

/// Hosts file syntax highlighting engine.
///
/// Performs full-line highlighting on NSTextStorage, recognizing the following elements:
/// - HostCat management block marker lines (orange bold)
/// - Pure comment lines (gray)
/// - IP addresses (blue)
/// - hostnames (green)
/// - Trailing comments (gray)
/// - Error lines (red semi-transparent background)
@MainActor
struct HostsSyntaxHighlighter {
    /// Default monospaced font.
    static let defaultFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    /// Highlight color palette.
    struct Colors {
        static let comment = NSColor.secondaryLabelColor
        static let ipAddress = NSColor.systemBlue
        static let hostname = NSColor.systemGreen
        static let marker = NSColor.systemOrange
        static let errorBackground = NSColor.systemRed.withAlphaComponent(0.1)
        static let defaultText = NSColor.labelColor
    }

    /// Performs full syntax highlighting on the entire textStorage.
    /// - Parameters:
    ///   - textStorage: The text storage to highlight.
    ///   - errorLines: Set of error line numbers detected by the parser (1-indexed).
    static func highlight(_ textStorage: NSTextStorage, errorLines: Set<Int>) {
        let text = textStorage.string
        guard !text.isEmpty else { return }

        let fullRange = NSRange(location: 0, length: textStorage.length)

        textStorage.beginEditing()

        // 1. Reset to default style.
        let defaultAttrs: [NSAttributedString.Key: Any] = [
            .font: defaultFont,
            .foregroundColor: Colors.defaultText,
        ]
        textStorage.setAttributes(defaultAttrs, range: fullRange)

        // 2. Apply highlighting line by line.
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

        // Error line background.
        if isError {
            textStorage.addAttribute(.backgroundColor, value: Colors.errorBackground, range: fullLineRange)
        }

        // HostCat management block marker lines.
        if trimmed.hasPrefix(HostsImporter.beginMarkerPrefix) || trimmed == HostsImporter.endMarker {
            let markerAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: Colors.marker,
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold),
            ]
            textStorage.addAttributes(markerAttrs, range: lineRange)
            return
        }

        // Pure comment lines.
        if trimmed.hasPrefix("#") {
            textStorage.addAttribute(.foregroundColor, value: Colors.comment, range: lineRange)
            return
        }

        // Skip empty lines.
        guard !trimmed.isEmpty else { return }

        // Data line: IP hostname [alias...] [# comment]
        highlightDataLine(line, lineRange: lineRange, textStorage: textStorage)
    }

    /// Highlights a data line: IP in blue, hostname in green, trailing comment in gray.
    private static func highlightDataLine(
        _ line: String,
        lineRange: NSRange,
        textStorage: NSTextStorage
    ) {
        let nsLine = line as NSString

        // Find trailing comment.
        var bodyPart = line
        if let commentStart = findCommentStart(in: line) {
            let commentNSRange = NSRange(
                location: lineRange.location + commentStart,
                length: nsLine.length - commentStart
            )
            textStorage.addAttribute(.foregroundColor, value: Colors.comment, range: commentNSRange)
            bodyPart = String(line.prefix(commentStart))
        }

        // Split into tokens.
        let tokens = tokenize(bodyPart)
        guard let firstToken = tokens.first else { return }

        // First token is the IP.
        let ipRange = NSRange(
            location: lineRange.location + firstToken.offset,
            length: firstToken.length
        )
        textStorage.addAttribute(.foregroundColor, value: Colors.ipAddress, range: ipRange)

        // Remaining tokens are hostnames.
        for token in tokens.dropFirst() {
            let hostnameRange = NSRange(
                location: lineRange.location + token.offset,
                length: token.length
            )
            textStorage.addAttribute(.foregroundColor, value: Colors.hostname, range: hostnameRange)
        }
    }

    /// Finds the start position of a `#` comment in a line (ignoring special characters that may appear in IP addresses).
    private static func findCommentStart(in line: String) -> Int? {
        // In hosts format, `#` always starts a comment; there is no escaping.
        guard let range = line.range(of: "#") else { return nil }
        return line.distance(from: line.startIndex, to: range.lowerBound)
    }

    /// Token position information.
    private struct Token {
        let offset: Int
        let length: Int
    }

    /// Splits text into whitespace-separated tokens, recording each token's offset in the original text.
    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        let end = text.endIndex

        while index < end {
            // Skip whitespace.
            while index < end && (text[index] == " " || text[index] == "\t") {
                index = text.index(after: index)
            }

            guard index < end else { break }

            // Record token start.
            let tokenStart = index

            // Read non-whitespace characters.
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
