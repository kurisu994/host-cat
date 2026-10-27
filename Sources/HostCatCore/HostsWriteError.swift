import Foundation

/// 写入错误的底层细节。Helper 在 root 进程抛出错误时不知道用户的界面语言，
/// 因此携带 key + 参数，等到 `HostsWriteError.description(in:)` 再按请求语言翻译。
public enum WriteErrorDetail: Equatable, Sendable, ExpressibleByStringInterpolation {
    /// 已成型的文本（系统原文、其他层已翻译的消息、测试替身消息）。
    case raw(String)
    /// 需按语言翻译的格式串 key 与参数。
    case localized(key: String, arguments: [String])

    public init(stringLiteral value: String) {
        self = .raw(value)
    }

    /// 按语言生成最终文本。
    public func text(in language: AppLanguage) -> String {
        switch self {
        case let .raw(text):
            text
        case let .localized(key, arguments):
            LC.localizedFormat(key, arguments: arguments, language: language)
        }
    }

    // MARK: - 工厂（系统 strerror 原文作为参数保留，便于排障）

    static func readFileFailed(_ path: String) -> Self { .localized(key: "detail.read_file_failed", arguments: [path]) }
    static func writeSyscallFailed(_ reason: String) -> Self { .localized(key: "detail.write_syscall_failed", arguments: [reason]) }
    static func fsyncFailed(_ reason: String) -> Self { .localized(key: "detail.fsync_failed", arguments: [reason]) }
    static func chmodFailed(mode: String, reason: String) -> Self {
        .localized(key: "detail.chmod_failed", arguments: [mode, reason])
    }
    static func chownFailed(owner: String, reason: String) -> Self {
        .localized(key: "detail.chown_failed", arguments: [owner, reason])
    }
    static func renameFailed(_ reason: String) -> Self { .localized(key: "detail.rename_failed", arguments: [reason]) }
    static func removeTempFailed(_ reason: String) -> Self { .localized(key: "detail.remove_temp_failed", arguments: [reason]) }
    static func statFailed(_ reason: String) -> Self { .localized(key: "detail.stat_failed", arguments: [reason]) }
    static func realpathFailed(_ reason: String) -> Self { .localized(key: "detail.realpath_failed", arguments: [reason]) }
    static var contentEmpty: Self { .localized(key: "detail.content_empty", arguments: []) }
    static var missingBeginMarker: Self { .localized(key: "detail.missing_begin_marker", arguments: []) }
    static var missingEndMarker: Self { .localized(key: "detail.missing_end_marker", arguments: []) }
    static func missingSystemEntry(ip: String, hostname: String) -> Self {
        .localized(key: "detail.missing_system_entry", arguments: [ip, hostname])
    }
    static func contentTooLarge(bytes: Int) -> Self {
        .localized(key: "detail.content_too_large", arguments: [String(bytes)])
    }
    static func dnsLaunchFailed(path: String, reason: String) -> Self {
        .localized(key: "detail.dns_launch_failed", arguments: [path, reason])
    }
    static func dnsCommandFailed(command: String, status: Int32, stderr: String) -> Self {
        .localized(key: "detail.dns_command_failed", arguments: [command, String(status), stderr])
    }
}

/// Errors related to hosts file writing.
public enum HostsWriteError: Error, Equatable, LocalizedError, Sendable {
    /// The hosts file has immutable flags (schg / uchg) set and cannot be written.
    case fileImmutable
    /// expectedCurrentHostsHash does not match the current file hash, indicating the hosts file was modified outside HostCat.
    case hashMismatch
    /// 非强制写入却没有带上当前文件 hash。
    case missingExpectedHash
    /// /etc/hosts 的真实路径不是允许的 /private/etc/hosts。
    case refusedHostsPath
    /// Content validation failed (empty content, missing required system entries, or incomplete management block markers).
    case contentValidationFailed(WriteErrorDetail)
    /// mkstemp failed to create a temporary file.
    case tempFileCreationFailed(WriteErrorDetail)
    /// Writing to the temporary file or fsync failed.
    case writeFailed(WriteErrorDetail)
    /// rename(2) atomic replacement failed.
    case renameFailed(WriteErrorDetail)
    /// chmod / chown failed to set permissions or owner.
    case permissionSetFailed(WriteErrorDetail)
    /// DNS cache refresh failed (note: hosts has already been written successfully at this point).
    case dnsRefreshFailed(WriteErrorDetail)

    public var errorDescription: String? {
        description(in: .stored())
    }

    /// 按请求方选择的界面语言生成写入错误说明，供跨进程 Helper 回复使用。
    public func description(in language: AppLanguage) -> String {
        switch self {
        case .fileImmutable:
            LC.localizedString("write.error.file_immutable", language: language)
        case .hashMismatch:
            LC.localizedString("write.error.hash_mismatch", language: language)
        case .missingExpectedHash:
            LC.localizedString("write.error.missing_expected_hash", language: language)
        case .refusedHostsPath:
            LC.localizedString("write.error.refused_hosts_path", language: language)
        case let .contentValidationFailed(detail):
            String(
                format: LC.localizedString("write.error.content_validation_failed", language: language),
                detail.text(in: language)
            )
        case let .tempFileCreationFailed(detail):
            String(
                format: LC.localizedString("write.error.temp_file_creation_failed", language: language),
                detail.text(in: language)
            )
        case let .writeFailed(detail):
            String(format: LC.localizedString("write.error.write_failed", language: language), detail.text(in: language))
        case let .renameFailed(detail):
            String(format: LC.localizedString("write.error.rename_failed", language: language), detail.text(in: language))
        case let .permissionSetFailed(detail):
            String(
                format: LC.localizedString("write.error.permission_set_failed", language: language),
                detail.text(in: language)
            )
        case let .dnsRefreshFailed(detail):
            String(
                format: LC.localizedString("write.error.dns_refresh_failed", language: language),
                detail.text(in: language)
            )
        }
    }
}
