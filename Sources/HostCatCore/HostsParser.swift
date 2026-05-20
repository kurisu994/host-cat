import Foundation
import Network

public enum HostsParseError: Error, Equatable, LocalizedError, Sendable {
    case invalidIPAddress(lineNumber: Int, value: String)
    case missingHostname(lineNumber: Int)
    case invalidHostname(lineNumber: Int, value: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidIPAddress(lineNumber, value):
            "第 \(lineNumber) 行 IP 地址无效：\(value)"
        case let .missingHostname(lineNumber):
            "第 \(lineNumber) 行缺少 hostname"
        case let .invalidHostname(lineNumber, value):
            "第 \(lineNumber) 行 hostname 无效：\(value)"
        }
    }
}

public struct HostRecordSource: Equatable, Sendable {
    public var groupName: String?
    public var nodeName: String

    public init(groupName: String? = nil, nodeName: String) {
        self.groupName = groupName
        self.nodeName = nodeName
    }
}

public struct HostRecord: Equatable, Sendable {
    public var ipAddress: String
    public var hostnames: [String]
    public var comment: String?
    public var lineNumber: Int
    public var source: HostRecordSource?

    public init(
        ipAddress: String,
        hostnames: [String],
        comment: String? = nil,
        lineNumber: Int,
        source: HostRecordSource? = nil
    ) {
        self.ipAddress = ipAddress
        self.hostnames = hostnames
        self.comment = comment
        self.lineNumber = lineNumber
        self.source = source
    }

    public func attachingSource(_ source: HostRecordSource) -> HostRecord {
        HostRecord(
            ipAddress: ipAddress,
            hostnames: hostnames,
            comment: comment,
            lineNumber: lineNumber,
            source: source
        )
    }
}

public struct HostsParser: Sendable {
    public init() {}

    public func parse(_ content: String) throws -> [HostRecord] {
        var records: [HostRecord] = []
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            let line = String(rawLine)
            let split = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            let body = String(split.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let comment = split.count > 1
                ? String(split[1]).trimmingCharacters(in: .whitespaces)
                : nil

            guard !body.isEmpty else {
                continue
            }

            let tokens = body
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)

            guard let ipAddress = tokens.first else {
                continue
            }

            guard isValidIPAddress(ipAddress) else {
                throw HostsParseError.invalidIPAddress(lineNumber: lineNumber, value: ipAddress)
            }

            let hostnames = Array(tokens.dropFirst())
            guard !hostnames.isEmpty else {
                throw HostsParseError.missingHostname(lineNumber: lineNumber)
            }

            for hostname in hostnames where !isValidHostname(hostname) {
                throw HostsParseError.invalidHostname(lineNumber: lineNumber, value: hostname)
            }

            records.append(
                HostRecord(
                    ipAddress: ipAddress,
                    hostnames: hostnames,
                    comment: comment?.isEmpty == true ? nil : comment,
                    lineNumber: lineNumber
                )
            )
        }

        return records
    }

    private func isValidIPAddress(_ value: String) -> Bool {
        IPv4Address(value) != nil || IPv6Address(value) != nil
    }

    private func isValidHostname(_ value: String) -> Bool {
        let hostname = value.hasSuffix(".") ? String(value.dropLast()) : value
        guard !hostname.isEmpty, hostname.count <= 253 else {
            return false
        }

        return hostname.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            guard !label.isEmpty, label.count <= 63 else {
                return false
            }

            guard label.first != "-", label.last != "-" else {
                return false
            }

            return label.unicodeScalars.allSatisfy { scalar in
                CharacterSet.alphanumerics.contains(scalar) || scalar == "-"
            }
        }
    }
}
