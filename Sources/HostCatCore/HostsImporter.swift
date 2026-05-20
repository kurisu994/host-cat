import Foundation

public enum HostsBlockVersion: Equatable, Sendable {
    case v1
    case unknown(String)
}

public struct HostsImportResult: Equatable, Sendable {
    public var defaultNodeContent: String
    public var hasHostCatBlock: Bool
    public var blockVersion: HostsBlockVersion?
    public var isBlockValid: Bool
    public var encodingIssue: Bool

    public init(
        defaultNodeContent: String,
        hasHostCatBlock: Bool,
        blockVersion: HostsBlockVersion? = nil,
        isBlockValid: Bool = true,
        encodingIssue: Bool = false
    ) {
        self.defaultNodeContent = defaultNodeContent
        self.hasHostCatBlock = hasHostCatBlock
        self.blockVersion = blockVersion
        self.isBlockValid = isBlockValid
        self.encodingIssue = encodingIssue
    }
}

public struct HostsImporter: Sendable {
    public static let beginMarkerPrefix = "# --- HostCat Begin ("
    public static let endMarker = "# --- HostCat End ---"

    public init() {}

    public func importHosts(_ content: String) -> HostsImportResult {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

        let beginInfo = findBeginMarker(in: lines)
        let endIndex = findEndMarker(in: lines)

        if let begin = beginInfo {
            if endIndex == nil {
                return HostsImportResult(
                    defaultNodeContent: extractOutsideBlock(lines: lines, beginIndex: nil, endIndex: nil),
                    hasHostCatBlock: true,
                    blockVersion: begin.version,
                    isBlockValid: false,
                    encodingIssue: false
                )
            }

            guard case .v1 = begin.version else {
                return HostsImportResult(
                    defaultNodeContent: extractOutsideBlock(lines: lines, beginIndex: nil, endIndex: nil),
                    hasHostCatBlock: true,
                    blockVersion: begin.version,
                    isBlockValid: false,
                    encodingIssue: false
                )
            }

            let outsideContent = extractOutsideBlock(lines: lines, beginIndex: begin.index, endIndex: endIndex)
            return HostsImportResult(
                defaultNodeContent: outsideContent,
                hasHostCatBlock: true,
                blockVersion: .v1,
                isBlockValid: true,
                encodingIssue: false
            )
        } else if endIndex != nil {
            return HostsImportResult(
                defaultNodeContent: extractOutsideBlock(lines: lines, beginIndex: nil, endIndex: nil),
                hasHostCatBlock: true,
                blockVersion: nil,
                isBlockValid: false,
                encodingIssue: false
            )
        }

        return HostsImportResult(
            defaultNodeContent: content,
            hasHostCatBlock: false,
            blockVersion: nil,
            isBlockValid: true,
            encodingIssue: false
        )
    }

    public func importHostsWithFallback(data: Data) -> HostsImportResult {
        if let utf8String = String(data: data, encoding: .utf8) {
            return importHosts(utf8String)
        }

        if let latin1String = String(data: data, encoding: .isoLatin1) {
            var result = importHosts(latin1String)
            result.encodingIssue = true
            return result
        }

        return HostsImportResult(
            defaultNodeContent: "",
            hasHostCatBlock: false,
            encodingIssue: true
        )
    }

    private func findBeginMarker(in lines: [Substring]) -> (index: Int, version: HostsBlockVersion)? {
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(Self.beginMarkerPrefix) && trimmed.hasSuffix("---") {
                let versionPart = trimmed.dropFirst(Self.beginMarkerPrefix.count).dropLast(4)
                let versionString = String(versionPart).trimmingCharacters(in: .whitespaces)
                let version: HostsBlockVersion = (versionString == "v1") ? .v1 : .unknown(versionString)
                return (index, version)
            }
        }
        return nil
    }

    private func findEndMarker(in lines: [Substring]) -> Int? {
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == Self.endMarker {
                return index
            }
        }
        return nil
    }

    private func extractOutsideBlock(lines: [Substring], beginIndex: Int?, endIndex: Int?) -> String {
        var resultLines: [String] = []

        for (index, line) in lines.enumerated() {
            if let begin = beginIndex, let end = endIndex {
                if index < begin || index > end {
                    resultLines.append(String(line))
                }
            } else {
                resultLines.append(String(line))
            }
        }

        let content = resultLines.joined(separator: "\n")
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
