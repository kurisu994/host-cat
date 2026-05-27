import Foundation

/// Errors related to hosts file writing.
public enum HostsWriteError: Error, Equatable, LocalizedError, Sendable {
    /// The hosts file has immutable flags (schg / uchg) set and cannot be written.
    case fileImmutable
    /// expectedCurrentHostsHash does not match the current file hash, indicating the hosts file was modified outside HostCat.
    case hashMismatch
    /// Content validation failed (empty content, missing required system entries, or incomplete management block markers).
    case contentValidationFailed(String)
    /// mkstemp failed to create a temporary file.
    case tempFileCreationFailed(String)
    /// Writing to the temporary file or fsync failed.
    case writeFailed(String)
    /// rename(2) atomic replacement failed.
    case renameFailed(String)
    /// chmod / chown failed to set permissions or owner.
    case permissionSetFailed(String)
    /// DNS cache refresh failed (note: hosts has already been written successfully at this point).
    case dnsRefreshFailed(String)

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
        case let .contentValidationFailed(detail):
            String(
                format: LC.localizedString("write.error.content_validation_failed", language: language),
                detail
            )
        case let .tempFileCreationFailed(detail):
            String(
                format: LC.localizedString("write.error.temp_file_creation_failed", language: language),
                detail
            )
        case let .writeFailed(detail):
            String(format: LC.localizedString("write.error.write_failed", language: language), detail)
        case let .renameFailed(detail):
            String(format: LC.localizedString("write.error.rename_failed", language: language), detail)
        case let .permissionSetFailed(detail):
            String(
                format: LC.localizedString("write.error.permission_set_failed", language: language),
                detail
            )
        case let .dnsRefreshFailed(detail):
            String(
                format: LC.localizedString("write.error.dns_refresh_failed", language: language),
                detail
            )
        }
    }
}
