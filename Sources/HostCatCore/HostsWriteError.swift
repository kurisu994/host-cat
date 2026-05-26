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
