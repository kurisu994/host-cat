import Foundation

/// hosts 文件写入相关错误
public enum HostsWriteError: Error, Equatable, LocalizedError, Sendable {
    /// hosts 文件设置了 immutable flags（schg / uchg），不允许写入
    case fileImmutable
    /// expectedCurrentHostsHash 与当前文件 hash 不匹配，表示 hosts 在 HostCat 之外被修改
    case hashMismatch
    /// 写入内容校验失败（空内容、缺少系统默认条目或管理区块标记不完整）
    case contentValidationFailed(String)
    /// mkstemp 创建临时文件失败
    case tempFileCreationFailed(String)
    /// 写入临时文件或 fsync 失败
    case writeFailed(String)
    /// rename(2) 原子替换失败
    case renameFailed(String)
    /// chmod / chown 设置权限或属主失败
    case permissionSetFailed(String)
    /// DNS 缓存刷新失败（注意：此时 hosts 已写入成功）
    case dnsRefreshFailed(String)

    public var errorDescription: String? {
        switch self {
        case .fileImmutable:
            LC.writeErrorFileImmutable
        case .hashMismatch:
            LC.writeErrorHashMismatch
        case let .contentValidationFailed(detail):
            LC.writeErrorContentValidationFailed(detail)
        case let .tempFileCreationFailed(detail):
            LC.writeErrorTempFileCreationFailed(detail)
        case let .writeFailed(detail):
            LC.writeErrorWriteFailed(detail)
        case let .renameFailed(detail):
            LC.writeErrorRenameFailed(detail)
        case let .permissionSetFailed(detail):
            LC.writeErrorPermissionSetFailed(detail)
        case let .dnsRefreshFailed(detail):
            LC.writeErrorDNSRefreshFailed(detail)
        }
    }
}
