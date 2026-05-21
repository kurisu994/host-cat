import Foundation

public struct MergedHosts: Equatable, Sendable {
    public var text: String
    public var duplicateCount: Int
    public var records: [HostRecord]

    public init(text: String, duplicateCount: Int, records: [HostRecord]) {
        self.text = text
        self.duplicateCount = duplicateCount
        self.records = records
    }
}

public struct HostConflictEndpoint: Equatable, Sendable {
    public var ipAddress: String
    public var groupName: String?
    public var nodeName: String

    public init(ipAddress: String, groupName: String? = nil, nodeName: String) {
        self.ipAddress = ipAddress
        self.groupName = groupName
        self.nodeName = nodeName
    }
}

public struct HostConflict: Equatable, Sendable {
    public var hostname: String
    public var existing: HostConflictEndpoint
    public var incoming: HostConflictEndpoint

    public init(hostname: String, existing: HostConflictEndpoint, incoming: HostConflictEndpoint) {
        self.hostname = hostname
        self.existing = existing
        self.incoming = incoming
    }
}

public enum HostMergeError: Error, Equatable, Sendable {
    case conflicts([HostConflict])
}

public struct HostsMerger: Sendable {
    private struct NodeContext: Sendable {
        var groupName: String?
        var node: HostNode
    }

    private struct ParsedContext: Sendable {
        var groupName: String?
        var nodeName: String
        var records: [HostRecord]
    }

    private static let hostCatBeginHeader = "# --- HostCat Begin (v1) ---"
    private static let hostCatEndHeader = "# --- HostCat End ---"
    private static let sectionSeparator = "# =============================="
    private static let subsectionSeparator = "# ------------------------------"

    public init() {}

    public func merge(_ config: AppConfig) throws -> MergedHosts {
        let parser = HostsParser()
        let contexts = activeNodeContexts(in: config)
        let parsedContexts = try contexts.map { context in
            let source = HostRecordSource(groupName: context.groupName, nodeName: context.node.name)
            let records = try parser.parse(context.node.content).map { $0.attachingSource(source) }
            return ParsedContext(groupName: context.groupName, nodeName: context.node.name, records: records)
        }

        let conflicts = findConflicts(in: parsedContexts)
        guard conflicts.isEmpty else {
            throw HostMergeError.conflicts(conflicts)
        }

        return buildMergedHosts(from: parsedContexts)
    }

    private func activeNodeContexts(in config: AppConfig) -> [NodeContext] {
        var contexts = [
            NodeContext(groupName: nil, node: config.defaultNode)
        ]

        for group in config.groups {
            for node in group.nodes where node.isActive {
                contexts.append(NodeContext(groupName: group.name, node: node))
            }
        }

        return contexts
    }

    private func findConflicts(in contexts: [ParsedContext]) -> [HostConflict] {
        var firstSeen: [String: HostConflictEndpoint] = [:]
        var conflicts: [HostConflict] = []

        for context in contexts {
            for record in context.records {
                let incoming = HostConflictEndpoint(
                    ipAddress: record.ipAddress,
                    groupName: context.groupName,
                    nodeName: context.nodeName
                )

                for hostname in record.hostnames {
                    let key = "\(hostname.lowercased())\u{0}\(addressFamily(of: record.ipAddress))"
                    if let existing = firstSeen[key], existing.ipAddress != incoming.ipAddress {
                        conflicts.append(
                            HostConflict(hostname: hostname, existing: existing, incoming: incoming)
                        )
                    } else if firstSeen[key] == nil {
                        firstSeen[key] = incoming
                    }
                }
            }
        }

        return conflicts
    }

    private func buildMergedHosts(from contexts: [ParsedContext]) -> MergedHosts {
        var lines: [String] = [
            Self.hostCatBeginHeader,
            ""
        ]
        var seenEntryKeys: Set<String> = []
        var duplicateCount = 0
        var emittedRecords: [HostRecord] = []

        for context in contexts {
            lines.append(Self.sectionSeparator)
            if let groupName = context.groupName {
                lines.append("# [\(sanitizeCommentText(groupName))]")
                lines.append("")
                lines.append(Self.subsectionSeparator)
                lines.append("# \(sanitizeCommentText(context.nodeName))")
            } else {
                lines.append("# \(sanitizeCommentText(context.nodeName))")
            }

            for record in context.records {
                let uniqueHostnames = record.hostnames.filter { hostname in
                    let key = "\(record.ipAddress)\u{0}\(hostname.lowercased())"
                    if seenEntryKeys.contains(key) {
                        duplicateCount += 1
                        return false
                    }

                    seenEntryKeys.insert(key)
                    return true
                }

                guard !uniqueHostnames.isEmpty else {
                    continue
                }

                let emittedRecord = HostRecord(
                    ipAddress: record.ipAddress,
                    hostnames: uniqueHostnames,
                    comment: record.comment,
                    lineNumber: record.lineNumber,
                    source: record.source
                )
                emittedRecords.append(emittedRecord)
                lines.append(format(emittedRecord))
            }

            lines.append("")
        }

        lines.append(Self.hostCatEndHeader)
        lines.append("")

        return MergedHosts(
            text: lines.joined(separator: "\n"),
            duplicateCount: duplicateCount,
            records: emittedRecords
        )
    }

    private func format(_ record: HostRecord) -> String {
        let body = "\(record.ipAddress) \(record.hostnames.joined(separator: " "))"
        guard let comment = record.comment, !comment.isEmpty else {
            return body
        }

        return "\(body) # \(comment)"
    }

    private func addressFamily(of ipAddress: String) -> String {
        ipAddress.contains(":") ? "ipv6" : "ipv4"
    }

    private func sanitizeCommentText(_ value: String) -> String {
        let scalars = value.unicodeScalars.map { scalar in
            CharacterSet.newlines.contains(scalar) || CharacterSet.controlCharacters.contains(scalar)
                ? " "
                : String(scalar)
        }
        return scalars.joined().trimmingCharacters(in: .whitespaces)
    }
}
