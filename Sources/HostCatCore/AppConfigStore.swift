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
            "配置文件已损坏，已恢复为默认设置。"
        case let .unsupportedVersion(version):
            "配置文件版本 \(version) 暂不支持，已恢复为默认设置。"
        }
    }
}

public enum AppConfigStoreError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedConfigVersion(Int)
    case atomicReplaceFailed(errno: Int32)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedConfigVersion(version):
            "配置文件版本 \(version) 暂不支持。"
        case let .atomicReplaceFailed(errno):
            "配置文件原子替换失败，系统错误码：\(errno)。"
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

    public func load(defaultHosts: String) throws -> AppConfigLoadResult {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            let config = AppConfig.initial(defaultHosts: defaultHosts)
            try save(config)
            return AppConfigLoadResult(config: config, status: .createdDefault)
        }

        let data = try Data(contentsOf: configURL)
        let decodedConfig: AppConfig
        do {
            decodedConfig = try JSONDecoder.hostCatConfigDecoder.decode(AppConfig.self, from: data)
        } catch {
            return try recoverDefault(defaultHosts: defaultHosts, reason: .invalidJSON)
        }

        guard decodedConfig.configVersion == Self.currentConfigVersion else {
            return try recoverDefault(
                defaultHosts: defaultHosts,
                reason: .unsupportedVersion(decodedConfig.configVersion)
            )
        }

        return AppConfigLoadResult(config: decodedConfig, status: .loadedExisting)
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
        reason: AppConfigRecoveryReason
    ) throws -> AppConfigLoadResult {
        let config = AppConfig.initial(defaultHosts: defaultHosts)
        try save(config)
        return AppConfigLoadResult(config: config, status: .recoveredDefault(reason))
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
