import Darwin
import Foundation

public struct AppConfigLoadResult: Equatable, Sendable {
    public var config: AppConfig
    public var status: AppConfigLoadStatus

    public init(config: AppConfig, status: AppConfigLoadStatus) {
        self.config = config
        self.status = status
    }
}

public enum AppConfigLoadStatus: Equatable, Sendable {
    case loadedExisting
    case createdDefault
    case recoveredDefault(AppConfigRecoveryReason)
}

public enum AppConfigRecoveryReason: Equatable, LocalizedError, Sendable {
    case invalidJSON
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON:
            LC.recoveryInvalidJSON
        case let .unsupportedVersion(version):
            LC.recoveryUnsupportedVersion(version)
        }
    }
}

public enum AppConfigStoreError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedConfigVersion(Int)
    case atomicReplaceFailed(errno: Int32)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedConfigVersion(version):
            LC.configErrorUnsupportedVersion(version)
        case let .atomicReplaceFailed(errno):
            LC.configErrorAtomicReplaceFailed(errno: errno)
        }
    }
}

public struct AppConfigStore: Sendable {
    public static let currentConfigVersion = 1

    public var configURL: URL

    public init(configURL: URL = Self.defaultConfigURL()) {
        self.configURL = configURL
    }

    public static func defaultConfigURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.hostcat.app", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    public func load(defaultHosts: String, currentHostsHash: String? = nil) throws -> AppConfigLoadResult {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            let config = AppConfig.initial(defaultHosts: defaultHosts, currentHostsHash: currentHostsHash)
            try save(config)
            return AppConfigLoadResult(config: config, status: .createdDefault)
        }

        let data = try Data(contentsOf: configURL)
        let decodedConfig: AppConfig
        do {
            decodedConfig = try JSONDecoder.hostCatConfigDecoder.decode(AppConfig.self, from: data)
        } catch {
            try preserveRecoverableConfig(reason: "corrupt")
            return try recoverDefault(
                defaultHosts: defaultHosts,
                currentHostsHash: currentHostsHash,
                reason: .invalidJSON
            )
        }

        guard decodedConfig.configVersion == Self.currentConfigVersion else {
            try preserveRecoverableConfig(reason: "unsupported")
            return try recoverDefault(
                defaultHosts: defaultHosts,
                currentHostsHash: currentHostsHash,
                reason: .unsupportedVersion(decodedConfig.configVersion)
            )
        }

        var loadedConfig = normalizedForCurrentRules(decodedConfig)
        if let currentHostsHash,
           loadedConfig.state.lastAppliedHostsHash == nil,
           loadedConfig.state.lastExternalHostsHash == nil {
            loadedConfig.state.lastExternalHostsHash = currentHostsHash
        }

        return AppConfigLoadResult(config: loadedConfig, status: .loadedExisting)
    }

    public func save(_ config: AppConfig) throws {
        guard config.configVersion == Self.currentConfigVersion else {
            throw AppConfigStoreError.unsupportedConfigVersion(config.configVersion)
        }

        let parentURL = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)

        let tempURL = parentURL.appendingPathComponent(
            ".\(configURL.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )

        do {
            let data = try JSONEncoder.hostCatConfigEncoder.encode(config)
            try data.write(to: tempURL)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: tempURL.path
            )

            guard rename(tempURL.path, configURL.path) == 0 else {
                throw AppConfigStoreError.atomicReplaceFailed(errno: errno)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    private func recoverDefault(
        defaultHosts: String,
        currentHostsHash: String?,
        reason: AppConfigRecoveryReason
    ) throws -> AppConfigLoadResult {
        let config = AppConfig.initial(defaultHosts: defaultHosts, currentHostsHash: currentHostsHash)
        try save(config)
        return AppConfigLoadResult(config: config, status: .recoveredDefault(reason))
    }

    private func preserveRecoverableConfig(reason: String) throws {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return
        }

        let parentURL = configURL.deletingLastPathComponent()
        let preservedURL = parentURL.appendingPathComponent(
            "\(configURL.lastPathComponent).\(reason).\(timestampForPreservedConfig()).\(UUID().uuidString)",
            isDirectory: false
        )
        try FileManager.default.copyItem(at: configURL, to: preservedURL)
    }

    private func timestampForPreservedConfig() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    private func normalizedForCurrentRules(_ config: AppConfig) -> AppConfig {
        var normalized = config
        normalized.defaultNode.isActive = true
        for index in normalized.groups.indices {
            normalized.groups[index].isSingleSelect = false
        }
        return normalized
    }
}

extension JSONEncoder {
    static var hostCatConfigEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

extension JSONDecoder {
    static var hostCatConfigDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
