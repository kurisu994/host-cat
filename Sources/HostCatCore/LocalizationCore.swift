import Foundation

/// HostCat Core 模块本地化字符串封装
///
/// Core 模块不依赖 SwiftUI，使用 Foundation 的 NSLocalizedString 进行本地化。
/// 字符串资源通过 Bundle.module 访问（SPM 自动生成的资源 bundle）。
/// 当 Bundle.module 不可用时（如未启用 SPM 资源），回退到主 bundle。
public enum LC {
    // MARK: - Parser Errors
    public static func parserInvalidIPAddress(lineNumber: Int, value: String) -> String {
        String(format: localize("error.parser.invalid_ip"), lineNumber, value)
    }

    public static func parserMissingHostname(lineNumber: Int) -> String {
        String(format: localize("error.parser.missing_hostname"), lineNumber)
    }

    public static func parserInvalidHostname(lineNumber: Int, value: String) -> String {
        String(format: localize("error.parser.invalid_hostname"), lineNumber, value)
    }

    public static let parserEmptyContent = localize("error.parser.empty_content")

    // MARK: - Write Errors
    public static let writeErrorFileImmutable = localize("write.error.file_immutable")
    public static let writeErrorHashMismatch = localize("write.error.hash_mismatch")
    public static func writeErrorContentValidationFailed(_ detail: String) -> String {
        String(format: localize("write.error.content_validation_failed"), detail)
    }
    public static func writeErrorTempFileCreationFailed(_ detail: String) -> String {
        String(format: localize("write.error.temp_file_creation_failed"), detail)
    }
    public static func writeErrorWriteFailed(_ detail: String) -> String {
        String(format: localize("write.error.write_failed"), detail)
    }
    public static func writeErrorRenameFailed(_ detail: String) -> String {
        String(format: localize("write.error.rename_failed"), detail)
    }
    public static func writeErrorPermissionSetFailed(_ detail: String) -> String {
        String(format: localize("write.error.permission_set_failed"), detail)
    }
    public static func writeErrorDNSRefreshFailed(_ detail: String) -> String {
        String(format: localize("write.error.dns_refresh_failed"), detail)
    }

    // MARK: - Backup Errors
    public static let backupErrorDirectoryCreationFailed = localize("backup.error.directory_creation_failed")
    public static let backupErrorWriteFailed = localize("backup.error.write_failed")
    public static let backupErrorCleanupFailed = localize("backup.error.cleanup_failed")

    // MARK: - Config Errors
    public static func configErrorUnsupportedVersion(_ version: Int) -> String {
        String(format: localize("config.error.unsupported_version"), version)
    }
    public static func configErrorAtomicReplaceFailed(errno: Int32) -> String {
        String(format: localize("config.error.atomic_replace_failed"), errno)
    }
    public static let configErrorInvalidJSON = localize("config.error.invalid_json")

    // MARK: - Recovery Reasons
    public static let recoveryInvalidJSON = localize("recovery.invalid_json")
    public static func recoveryUnsupportedVersion(_ version: Int) -> String {
        String(format: localize("recovery.unsupported_version"), version)
    }

    // MARK: - Logger Messages
    public static func logMergeSuccess(records: Int, duplicates: Int) -> String {
        String(format: localize("log.merge_success"), records, duplicates)
    }
    public static func logMergeConflicts(count: Int) -> String {
        String(format: localize("log.merge_conflicts"), count)
    }
    public static func logMergeFailed(_ message: String) -> String {
        String(format: localize("log.merge_failed"), message)
    }
    public static func logWriteSuccess(hashPrefix: String) -> String {
        String(format: localize("log.write_success"), hashPrefix)
    }
    public static func logWriteFailed(_ message: String) -> String {
        String(format: localize("log.write_failed"), message)
    }
    public static func logBackupCreated(_ filename: String) -> String {
        String(format: localize("log.backup_created"), filename)
    }
    public static func logBackupFailed(_ message: String) -> String {
        String(format: localize("log.backup_failed"), message)
    }
    public static func logBackupCleaned(_ filename: String) -> String {
        String(format: localize("log.backup_cleaned"), filename)
    }
    public static func logBackupCleanFailed(_ filename: String) -> String {
        String(format: localize("log.backup_clean_failed"), filename)
    }

    // MARK: - Helper Messages
    public static let helperNotInstalled = localize("helper.not_installed")
    public static let helperConnectionFailed = localize("helper.connection_failed")
    public static let helperRegistrationFailed = localize("helper.registration_failed")
    public static let helperAuthenticationFailed = localize("helper.authentication_failed")

    // MARK: - MenuBarViewModel Messages
    public static let configSaveFailed = localize("menubar.config_save_failed")
    public static let externalModificationDetected = localize("menubar.external_modification")
    public static func conflictsDetected(_ count: Int) -> String {
        String(format: localize("menubar.conflicts_detected"), count)
    }
    public static func hostsNotApplied(_ message: String) -> String {
        String(format: localize("menubar.hosts_not_applied"), message)
    }

    // MARK: - Logger Messages (MenuBarViewModel)
    public static let logConfigPersistSuccess = localize("log.config_persist_success")
    public static func logConfigPersistFailed(_ message: String) -> String {
        String(format: localize("log.config_persist_failed"), message)
    }
    public static let logDraftPersistSuccess = localize("log.draft_persist_success")
    public static func logDraftPersistFailed(_ message: String) -> String {
        String(format: localize("log.draft_persist_failed"), message)
    }
    public static func logMergePreview(_ records: Int, _ duplicates: Int) -> String {
        String(format: localize("log.merge_preview"), records, duplicates)
    }
    public static func logPreviewConflicts(_ count: Int) -> String {
        String(format: localize("log.preview_conflicts"), count)
    }
    public static func logPreviewMergeFailed(_ message: String) -> String {
        String(format: localize("log.preview_merge_failed"), message)
    }
    public static let logExternalModification = localize("log.external_modification")
    public static func logApplyFailed(_ prefix: String, _ message: String) -> String {
        String(format: localize("log.apply_failed"), prefix, message)
    }

    // MARK: - HelperRegistrationManager Messages
    public static let helperStatusNotRegistered = localize("helper.status.not_registered")
    public static let helperStatusEnabled = localize("helper.status.enabled")
    public static let helperStatusRequiresApproval = localize("helper.status.requires_approval")
    public static let helperStatusNotFound = localize("helper.status.not_found")
    public static let helperRegisterFailed = localize("helper.register_failed")
    public static let launchAtLoginFailed = localize("helper.launch_at_login_failed")
    public static let errorUnknown = localize("error.unknown")

    // MARK: - Private

    private static func localize(_ key: String) -> String {
        let bundle = Bundle.module ?? Bundle.main
        return NSLocalizedString(key, tableName: "LocalizableCore", bundle: bundle, value: key, comment: "")
    }
}

private extension Bundle {
    static var module: Bundle? {
        // SPM 自动生成的 Bundle.module，如果资源已正确配置则可用
        // 在 Xcode 构建中，如果未启用 SPM 资源，则返回 nil
        #if SWIFT_PACKAGE
        return Bundle(identifier: "HostCatCore")
        #else
        return nil
        #endif
    }
}
