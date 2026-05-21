import Foundation

public enum HostsBlockVersion: Equatable, Sendable {
    case v1
    case unknown(String)
}

public struct HostsImportResult: Equatable, Sendable {
    public var defaultNodeContent: String
    public var decodedContent: String
    public var currentHostsHash: String
    public var hasHostCatBlock: Bool
    public var blockVersion: HostsBlockVersion?
    public var isBlockValid: Bool
    public var encodingIssue: Bool

    public init(
        defaultNodeContent: String,
        decodedContent: String,
        currentHostsHash: String,
        hasHostCatBlock: Bool,
        blockVersion: HostsBlockVersion? = nil,
        isBlockValid: Bool = true,
        encodingIssue: Bool = false
    ) {
        self.defaultNodeContent = defaultNodeContent
        self.decodedContent = decodedContent
        self.currentHostsHash = currentHostsHash
        self.hasHostCatBlock = hasHostCatBlock
        self.blockVersion = blockVersion
        self.isBlockValid = isBlockValid
        self.encodingIssue = encodingIssue
    }
}

public struct HostsImporter: Sendable {
    public static let beginMarkerPrefix = "# --- HostCat Begin ("
    private static let beginMarkerSuffix = ") ---"
    public static let endMarker = "# --- HostCat End ---"

    public init() {}

    public func importHosts(_ content: String) -> HostsImportResult {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        let currentHostsHash = HostsHash.sha256Hex(content)

        func makeResult(
            defaultNodeContent: String,
            hasHostCatBlock: Bool,
            blockVersion: HostsBlockVersion? = nil,
            isBlockValid: Bool = true,
            encodingIssue: Bool = false
        ) -> HostsImportResult {
            HostsImportResult(
                defaultNodeContent: defaultNodeContent,
                decodedContent: content,
                currentHostsHash: currentHostsHash,
                hasHostCatBlock: hasHostCatBlock,
                blockVersion: blockVersion,
                isBlockValid: isBlockValid,
                encodingIssue: encodingIssue
            )
        }

        let beginInfo = findBeginMarker(in: lines)
        let firstEndIndex = findEndMarker(in: lines)

        if let begin = beginInfo {
            let endIndex = findEndMarker(in: lines, after: begin.index)
            if let firstEndIndex, firstEndIndex < begin.index, endIndex == nil {
                return makeResult(
                    defaultNodeContent: extractOutsideBlock(lines: lines, beginIndex: nil, endIndex: firstEndIndex),
                    hasHostCatBlock: true,
                    blockVersion: nil,
                    isBlockValid: false,
                    encodingIssue: false
                )
            }

            if endIndex == nil {
                return makeResult(
                    defaultNodeContent: extractOutsideBlock(lines: lines, beginIndex: begin.index, endIndex: nil),
                    hasHostCatBlock: true,
                    blockVersion: begin.version,
                    isBlockValid: false,
                    encodingIssue: false
                )
            }

            guard case .v1 = begin.version else {
                return makeResult(
                    defaultNodeContent: extractOutsideBlock(lines: lines, beginIndex: begin.index, endIndex: endIndex),
                    hasHostCatBlock: true,
                    blockVersion: begin.version,
                    isBlockValid: false,
                    encodingIssue: false
                )
            }

            let outsideContent = extractOutsideBlock(lines: lines, beginIndex: begin.index, endIndex: endIndex)
            return makeResult(
                defaultNodeContent: outsideContent,
                hasHostCatBlock: true,
                blockVersion: .v1,
                isBlockValid: true,
                encodingIssue: false
            )
        } else if let firstEndIndex {
            return makeResult(
                defaultNodeContent: extractOutsideBlock(lines: lines, beginIndex: nil, endIndex: firstEndIndex),
                hasHostCatBlock: true,
                blockVersion: nil,
                isBlockValid: false,
                encodingIssue: false
            )
        }

        let defaultContent = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : content
        return makeResult(
            defaultNodeContent: defaultContent,
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
            decodedContent: "",
            currentHostsHash: HostsHash.sha256Hex(""),
            hasHostCatBlock: false,
            encodingIssue: true
        )
    }

    private func findBeginMarker(in lines: [Substring]) -> (index: Int, version: HostsBlockVersion)? {
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(Self.beginMarkerPrefix) && trimmed.hasSuffix(Self.beginMarkerSuffix) {
                let versionPart = trimmed
                    .dropFirst(Self.beginMarkerPrefix.count)
                    .dropLast(Self.beginMarkerSuffix.count)
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

    private func findEndMarker(in lines: [Substring], after beginIndex: Int) -> Int? {
        for (index, line) in lines.enumerated() where index > beginIndex {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == Self.endMarker {
                return index
            }
        }
        return nil
    }

    private func extractOutsideBlock(lines: [Substring], beginIndex: Int?, endIndex: Int?) -> String {
        if let begin = beginIndex, let end = endIndex {
            let before = lines[..<begin].map(String.init)
            let afterStart = lines.index(lines.startIndex, offsetBy: end + 1)
            let after = lines[afterStart...].map(String.init)
            var resultLines = before
            if !before.isEmpty, !after.isEmpty {
                resultLines.append("")
            }
            resultLines.append(contentsOf: after)
            let content = resultLines.joined(separator: "\n")
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let begin = beginIndex {
            let content = lines[..<begin].map(String.init).joined(separator: "\n")
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let end = endIndex {
            let content = lines[..<end].map(String.init).joined(separator: "\n")
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let resultLines = lines.map(String.init)
        let content = resultLines.joined(separator: "\n")
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
